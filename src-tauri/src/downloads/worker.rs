use super::{
    StopIntent, TaskState,
    files::Reservation,
    journal::{ReservationRecord, ResumeCheckpoint},
    manager::{Inner, Job},
    resume::{ResumeDecision, decide, strong_etag},
};
use crate::error::{AppError, ErrorCode, Result};
use std::{
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::io::{AsyncSeekExt, AsyncWriteExt};

struct Progress {
    bytes: u64,
    total: Option<u64>,
    etag: Option<String>,
}

pub(super) async fn run(owner: Arc<Inner>, job: Job) {
    let Job {
        id,
        attempt,
        url,
        reservation,
        control,
        checkpoint,
        resume,
    } = job;
    let permit = tokio::select! { biased; _ = control.cancel.cancelled() => None, result = owner.slots.clone().acquire_owned() => result.ok() };
    let mut reservation = Some(reservation);
    let mut progress = Progress {
        bytes: checkpoint.committed_bytes,
        total: checkpoint.total_bytes,
        etag: checkpoint.etag.clone(),
    };
    let writer = {
        let reservation = reservation.take().unwrap();
        tokio::task::spawn_blocking(move || {
            let result = reservation.writer();
            (reservation, result)
        })
        .await
    };
    let (owned, writer) = match writer {
        Ok(value) => value,
        Err(error) => {
            owner.report_failure(
                &id,
                &attempt,
                AppError::with_source(ErrorCode::Storage, "下载文件打开异常终止", error),
            );
            return;
        }
    };
    reservation = Some(owned);
    let mut file = match writer {
        Ok(file) => tokio::fs::File::from_std(file),
        Err(error) => {
            reservation.take().unwrap().retain();
            owner.report_failure(&id, &attempt, storage(error));
            return;
        }
    };
    let result = if permit.is_none() {
        Err(cancelled())
    } else {
        match owner
            .change(id.clone(), attempt.clone(), |record| {
                record.task.state = TaskState::Running
            })
            .await
        {
            Ok(_) => {
                transfer(
                    &owner,
                    &id,
                    &attempt,
                    &url,
                    &control.cancel,
                    &checkpoint,
                    resume,
                    &mut file,
                    &mut reservation,
                    &mut progress,
                )
                .await
            }
            Err(error) => Err(error),
        }
    };
    // A requested stop waits for pending writes and durable checkpoint publication.
    let flushed = file.flush().await.map_err(storage);
    let synced = file.sync_all().await.map_err(storage);
    drop(file.into_std().await);
    let settled = flushed.and(synced);
    let intent = control
        .cancel
        .is_cancelled()
        .then(|| *control.intent.lock().unwrap());
    if intent == Some(StopIntent::Cancel) {
        let owned = reservation.take().unwrap();
        let cleanup = tokio::task::spawn_blocking(move || owned.cleanup().map_err(storage))
            .await
            .map_err(|error| AppError::with_source(ErrorCode::Storage, "清理下载异常终止", error))
            .and_then(|result| result);
        match cleanup {
            Ok(()) => {
                if let Err(error) = owner
                    .change(id.clone(), attempt.clone(), |record| {
                        record.reservation = None;
                        record.task.has_partial = false;
                        record.task.can_resume = false;
                        record.task.state = TaskState::Cancelled;
                        record.task.error = None;
                    })
                    .await
                {
                    owner.report_failure(&id, &attempt, error);
                }
            }
            Err(error) => owner.report_failure(&id, &attempt, error),
        }
        return;
    }
    // Never publish a checkpoint when flush/sync failed. The previous committed
    // offset remains authoritative; retained extra bytes are truncated on recovery.
    let checkpoint_result =
        settle_checkpoint(&owner, &id, &attempt, &mut reservation, &progress, settled).await;
    if let Err(error) = checkpoint_result {
        reservation.take().unwrap().retain();
        owner.report_failure(&id, &attempt, error);
        return;
    }
    if intent.is_some() || result.is_err() {
        reservation.take().unwrap().retain();
        let error = result
            .err()
            .filter(|error| error.code != ErrorCode::Cancelled)
            .map(|error| error.reported("download transfer").message);
        let state = if error.is_some() {
            TaskState::Failed
        } else {
            TaskState::Paused
        };
        if let Err(error) = owner
            .change(id.clone(), attempt.clone(), move |record| {
                record.task.state = state;
                record.task.error = error;
            })
            .await
        {
            owner.report_failure(&id, &attempt, error);
        }
        return;
    }
    let mut owned = reservation.take().unwrap();
    let owner_clone = owner.clone();
    let task_id = id.clone();
    let attempt_id = attempt.clone();
    let finalized = tokio::task::spawn_blocking(move || {
        let result = (|| -> Result<()> {
            let record = owned.publication_intent().map_err(storage)?;
            let checkpoint = record.checkpoint.clone();
            owner_clone.try_change_blocking(&task_id, &attempt_id, |stored| {
                if control.cancel.is_cancelled() {
                    return Err(cancelled());
                }
                stored.task.state = TaskState::Finalizing;
                stored.task.filename = record.filename.clone();
                stored.reservation = Some(record.clone());
                Ok(())
            })?;
            owned.publish().map_err(storage)?;
            owner_clone.change_blocking(&task_id, &attempt_id, |stored| {
                stored.task.state = TaskState::Completed;
                stored.task.file_available = true;
                stored.task.has_partial = false;
                stored.task.can_resume = false;
                stored.task.error = None;
                stored.completed_identity = Some(checkpoint.file_identity.clone());
            })?;
            Ok(())
        })();
        match result {
            Ok(()) => owned.complete().map_err(storage),
            Err(error) if error.code == ErrorCode::Cancelled => {
                if *control.intent.lock().unwrap() == StopIntent::Cancel {
                    owned.cleanup().map_err(storage)?;
                    owner_clone.change_blocking(&task_id, &attempt_id, |record| {
                        record.task.state = TaskState::Cancelled;
                        record.task.has_partial = false;
                        record.task.can_resume = false;
                        record.reservation = None;
                    })?;
                } else {
                    owned.retain();
                    owner_clone.change_blocking(&task_id, &attempt_id, |record| {
                        record.task.state = TaskState::Paused
                    })?;
                }
                Ok(())
            }
            Err(error) => {
                owned.retain();
                Err(error)
            }
        }
    })
    .await
    .map_err(|error| AppError::with_source(ErrorCode::Storage, "下载发布异常终止", error))
    .and_then(|result| result);
    if let Err(error) = finalized {
        owner.report_failure(&id, &attempt, error);
    }
    drop(permit);
}

#[allow(clippy::too_many_arguments)]
async fn transfer(
    owner: &Arc<Inner>,
    id: &str,
    attempt: &str,
    url: &str,
    cancellation: &tokio_util::sync::CancellationToken,
    checkpoint: &ResumeCheckpoint,
    resume: bool,
    file: &mut tokio::fs::File,
    reservation: &mut Option<Reservation>,
    progress: &mut Progress,
) -> Result<()> {
    let mut request = owner
        .client
        .get(url)
        .header("Referer", "https://scgc.video.play/")
        .header("Accept-Encoding", "identity");
    if resume {
        request = request
            .header("Range", format!("bytes={}-", checkpoint.committed_bytes))
            .header("If-Range", checkpoint.etag.as_deref().unwrap_or(""));
    }
    let response = tokio::select! { biased; _ = cancellation.cancelled() => return Err(cancelled()), result = tokio::time::timeout(owner.config.header_timeout, request.send()) => result.map_err(|error| AppError::with_source(ErrorCode::Timeout, "视频服务响应超时", error))?.map_err(network)? };
    if resume {
        match decide(
            checkpoint,
            response.status(),
            response.headers(),
            file.metadata().await.map_err(storage)?.len(),
        ) {
            ResumeDecision::Append {
                offset,
                total,
                etag,
            } => {
                progress.bytes = offset;
                progress.total = Some(total);
                progress.etag = Some(etag);
            }
            ResumeDecision::AlreadyComplete => return Ok(()),
            ResumeDecision::RestartRequired { reason } => {
                progress.etag = None;
                return Err(AppError::new(ErrorCode::Upstream, reason));
            }
        }
    } else {
        if response.status() != 200 {
            return Err(AppError::new(
                ErrorCode::Upstream,
                format!("视频下载失败（HTTP {}）", response.status().as_u16()),
            ));
        }
        progress.total = response.content_length();
        progress.etag = response
            .headers()
            .get("etag")
            .and_then(|value| value.to_str().ok())
            .filter(|value| strong_etag(value))
            .map(str::to_owned);
    }
    validate_media(&response)?;
    file.seek(std::io::SeekFrom::Start(progress.bytes))
        .await
        .map_err(storage)?;
    owner.progress(id, attempt, progress.bytes, progress.total, true);
    let mut response = response;
    let mut emitted = Instant::now();
    let mut checkpointed = Instant::now();
    loop {
        let chunk = tokio::select! { biased; _ = cancellation.cancelled() => return Err(cancelled()), result = response.chunk() => result.map_err(network)? };
        let Some(chunk) = chunk else {
            break;
        };
        if progress
            .total
            .is_some_and(|total| progress.bytes.saturating_add(chunk.len() as u64) > total)
        {
            return Err(AppError::new(
                ErrorCode::Upstream,
                "视频数据长度超过声明长度",
            ));
        }
        file.write_all(&chunk).await.map_err(storage)?;
        progress.bytes += chunk.len() as u64;
        let publish = emitted.elapsed() >= Duration::from_millis(100);
        owner.progress(id, attempt, progress.bytes, progress.total, publish);
        if publish {
            emitted = Instant::now();
        }
        if checkpointed.elapsed() >= Duration::from_secs(1) {
            file.flush().await.map_err(storage)?;
            file.sync_all().await.map_err(storage)?;
            save_checkpoint(owner, id, attempt, reservation, progress).await?;
            checkpointed = Instant::now();
        }
    }
    if progress.total.is_some_and(|total| progress.bytes != total) {
        return Err(AppError::new(
            ErrorCode::Upstream,
            "视频数据未完整接收，请重试",
        ));
    }
    Ok(())
}

async fn settle_checkpoint(
    owner: &Arc<Inner>,
    id: &str,
    attempt: &str,
    reservation: &mut Option<Reservation>,
    progress: &Progress,
    settled: Result<()>,
) -> Result<()> {
    settled?;
    save_checkpoint(owner, id, attempt, reservation, progress).await
}

async fn save_checkpoint(
    owner: &Arc<Inner>,
    id: &str,
    attempt: &str,
    reservation: &mut Option<Reservation>,
    progress: &Progress,
) -> Result<()> {
    let mut owned = reservation.take().unwrap();
    let (bytes, total, etag) = (progress.bytes, progress.total, progress.etag.clone());
    let (owned, result) = tokio::task::spawn_blocking(move || {
        let result = owned.checkpoint(bytes, total, etag).map_err(storage);
        (owned, result)
    })
    .await
    .map_err(|error| AppError::with_source(ErrorCode::Storage, "下载进度保存异常终止", error))?;
    *reservation = Some(owned);
    let record: ReservationRecord = result?;
    owner
        .change(id.into(), attempt.into(), move |stored| {
            stored.task.received_bytes = record.checkpoint.committed_bytes;
            stored.task.total_bytes = record.checkpoint.total_bytes;
            stored.task.can_resume = record.checkpoint.resumable();
            stored.reservation = Some(record);
        })
        .await?;
    Ok(())
}

fn validate_media(response: &reqwest::Response) -> Result<()> {
    let kind = response
        .headers()
        .get("content-type")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("")
        .split(';')
        .next()
        .unwrap_or("")
        .trim();
    if !kind.eq_ignore_ascii_case("video/mp4")
        && !kind.eq_ignore_ascii_case("application/octet-stream")
    {
        return Err(AppError::new(
            ErrorCode::Upstream,
            "视频服务返回了非视频内容",
        ));
    }
    if response
        .headers()
        .get("content-encoding")
        .is_some_and(|value| value != "identity")
    {
        return Err(AppError::new(
            ErrorCode::Upstream,
            "视频服务返回了不支持的编码",
        ));
    }
    Ok(())
}

fn cancelled() -> AppError {
    AppError::new(ErrorCode::Cancelled, "下载已停止")
}
pub(super) fn storage(error: std::io::Error) -> AppError {
    AppError::with_source(ErrorCode::Storage, "无法保存或清理下载文件", error)
}
fn network(error: reqwest::Error) -> AppError {
    AppError::with_source(
        if error.is_timeout() {
            ErrorCode::Timeout
        } else {
            ErrorCode::Upstream
        },
        if error.is_timeout() {
            "视频传输超时，请重试"
        } else {
            "视频传输中断，请重试"
        },
        error.without_url(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::Write,
        pin::Pin,
        task::{Context, Poll},
    };
    use tokio::io::AsyncWrite;
    struct FailedFlush;
    impl AsyncWrite for FailedFlush {
        fn poll_write(
            self: Pin<&mut Self>,
            _: &mut Context<'_>,
            bytes: &[u8],
        ) -> Poll<std::io::Result<usize>> {
            Poll::Ready(Ok(bytes.len()))
        }
        fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Ready(Err(std::io::Error::other("injected flush failure")))
        }
        fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Ready(Ok(()))
        }
    }

    #[tokio::test]
    async fn failed_writer_settlement_never_publishes_unsynchronized_progress() {
        for failure in ["flush", "sync"] {
            let root = tempfile::tempdir().unwrap();
            let directory = super::super::files::DownloadDirectory::open(root.path()).unwrap();
            let (mut file, mut reservation) = directory.reserve("clip.mp4").unwrap();
            let initial = reservation
                .upgrade("task".into(), "attempt".into())
                .unwrap();
            file.write_all(b"uncommitted bytes").unwrap();
            file.flush().unwrap();
            drop(file);
            let manager = super::super::DownloadManager::new(Default::default()).unwrap();
            let mut reservation = Some(reservation);
            let settled = if failure == "flush" {
                FailedFlush.flush().await.map_err(storage)
            } else {
                Err(storage(std::io::Error::other("injected sync failure")))
            };
            assert!(
                settle_checkpoint(
                    &manager.inner,
                    "task",
                    "attempt",
                    &mut reservation,
                    &Progress {
                        bytes: 17,
                        total: Some(100),
                        etag: Some("\"stable\"".into())
                    },
                    settled
                )
                .await
                .is_err()
            );
            let disk: ReservationRecord = crate::storage::read_json(
                &root.path().join(format!(".sctv-dl-{}.json", initial.id)),
                4096,
            )
            .unwrap()
            .unwrap();
            assert_eq!(disk.checkpoint.committed_bytes, 0);
            reservation.take().unwrap().retain();
            assert_eq!(
                std::fs::read(root.path().join(format!(".sctv-dl-{}.part", initial.id))).unwrap(),
                b"uncommitted bytes"
            );
            manager.shutdown().await;
        }
    }
}
