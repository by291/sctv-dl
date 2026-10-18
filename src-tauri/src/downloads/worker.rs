use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use tokio::io::{AsyncSeekExt, AsyncWriteExt};

use super::{
    StopIntent, TaskState,
    errors::{network, storage, with_secondary},
    files::Reservation,
    journal::{ReservationRecord, ResumeCheckpoint},
    manager::{Inner, Job},
    resume::{ResumeDecision, decide, strong_etag},
};
use crate::error::{AppError, ErrorCode, Result};

struct Progress {
    bytes: u64,
    total: Option<u64>,
    etag: Option<String>,
}

/// Carries task/attempt identity and cancellation together through every worker phase.
struct Attempt {
    owner: Arc<Inner>,
    id: String,
    attempt: String,
    control: Arc<super::manager::Control>,
}

/// The writer is closed before its reservation can move into publication or cleanup.
struct TransferWriter {
    file: tokio::fs::File,
    reservation: Option<Reservation>,
}

impl TransferWriter {
    async fn acquire(reservation: Reservation) -> Result<Self> {
        tokio::task::spawn_blocking(move || match reservation.writer() {
            Ok(file) => Ok(Self {
                file: tokio::fs::File::from_std(file),
                reservation: Some(reservation),
            }),
            Err(error) => {
                reservation.retain();
                Err(storage(error))
            }
        })
        .await
        .map_err(|error| AppError::with_source(ErrorCode::Storage, "下载文件打开异常终止", error))?
    }

    async fn settle(mut self) -> (Option<Reservation>, Result<()>) {
        // Await pending writes before closing the file; failed barriers keep the old checkpoint.
        let flushed = self.file.flush().await.map_err(storage);
        let synced = self.file.sync_all().await.map_err(storage);
        drop(self.file.into_std().await);
        (self.reservation, combine_results(flushed, synced))
    }
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
    let attempt = Attempt {
        owner,
        id,
        attempt,
        control,
    };
    if let Err(error) = run_attempt(&attempt, url, reservation, checkpoint, resume).await {
        attempt
            .owner
            .records
            .report_failure(&attempt.id, &attempt.attempt, error);
    }
}

async fn run_attempt(
    attempt: &Attempt,
    url: String,
    reservation: Reservation,
    checkpoint: ResumeCheckpoint,
    resume: bool,
) -> Result<()> {
    let transfer_slot = tokio::select! {
        biased;
        _ = attempt.control.cancel.cancelled() => None,
        result = attempt.owner.slots.clone().acquire_owned() => result.ok(),
    };
    let mut writer = TransferWriter::acquire(reservation).await?;
    let mut progress = Progress {
        bytes: checkpoint.committed_bytes,
        total: checkpoint.total_bytes,
        etag: checkpoint.etag.clone(),
    };

    let transfer_result = if transfer_slot.is_none() {
        Err(cancelled())
    } else {
        match attempt
            .owner
            .records
            .change(attempt.id.clone(), attempt.attempt.clone(), |record| {
                record.task.state = TaskState::Running
            })
            .await
        {
            Ok(_) => {
                transfer(
                    attempt,
                    &url,
                    &checkpoint,
                    resume,
                    &mut writer,
                    &mut progress,
                )
                .await
            }
            Err(error) => Err(error),
        }
    };

    let (mut reservation, settled) = writer.settle().await;

    let intent = attempt
        .control
        .cancel
        .is_cancelled()
        .then(|| *attempt.control.intent.lock().unwrap());
    if intent == Some(StopIntent::Cancel) {
        let cleanup = cancel_partial(attempt, reservation.take().unwrap()).await;
        // Expected cancellation stays quiet, but actual transfer and cleanup failures survive.
        return combine_results(
            combine_results(unexpected(transfer_result), settled),
            cleanup,
        );
    }

    let checkpoint_result = settle_checkpoint(
        &attempt.owner,
        &attempt.id,
        &attempt.attempt,
        &mut reservation,
        &progress,
        settled,
    )
    .await;
    if let Err(error) = checkpoint_result {
        if let Some(reservation) = reservation {
            reservation.retain();
        }
        return Err(with_secondary(
            error,
            unexpected(transfer_result),
            "transfer",
        ));
    }

    if intent.is_some() || transfer_result.is_err() {
        reservation.take().unwrap().retain();
        return retain_outcome(attempt, transfer_result).await;
    }

    publish(attempt, reservation.take().unwrap()).await
}

fn unexpected(result: Result<()>) -> Result<()> {
    match result {
        Err(error) if error.code == ErrorCode::Cancelled => Ok(()),
        result => result,
    }
}

fn combine_results(primary: Result<()>, secondary: Result<()>) -> Result<()> {
    match primary {
        Ok(()) => secondary,
        Err(error) => Err(with_secondary(error, secondary, "settlement/cleanup")),
    }
}

async fn cancel_partial(attempt: &Attempt, reservation: Reservation) -> Result<()> {
    tokio::task::spawn_blocking(move || reservation.cleanup().map_err(storage))
        .await
        .map_err(|error| AppError::with_source(ErrorCode::Storage, "清理下载异常终止", error))??;

    attempt
        .owner
        .records
        .change(attempt.id.clone(), attempt.attempt.clone(), |record| {
            record.reservation = None;
            record.task.has_partial = false;
            record.task.can_resume = false;
            record.task.state = TaskState::Cancelled;
            record.task.error = None;
        })
        .await?;
    Ok(())
}

async fn retain_outcome(attempt: &Attempt, transfer: Result<()>) -> Result<()> {
    let error = unexpected(transfer).err();
    let message = error.as_ref().map(|error| error.message.clone());
    let state = if error.is_some() {
        TaskState::Failed
    } else {
        TaskState::Paused
    };

    let saved = attempt
        .owner
        .records
        .change(attempt.id.clone(), attempt.attempt.clone(), move |record| {
            record.task.state = state;
            record.task.error = message;
        })
        .await
        .map(|_| ());

    if let Some(error) = error {
        if saved.is_err() {
            return Err(with_secondary(error, saved, "save retained outcome"));
        }
        error.reported("download transfer");
    } else {
        saved?;
    }
    Ok(())
}

async fn publish(attempt: &Attempt, mut owned: Reservation) -> Result<()> {
    let attempt = Attempt {
        owner: attempt.owner.clone(),
        id: attempt.id.clone(),
        attempt: attempt.attempt.clone(),
        control: attempt.control.clone(),
    };
    tokio::task::spawn_blocking(move || {
        let result = (|| -> Result<()> {
            let record = owned.publication_intent().map_err(storage)?;
            let checkpoint = record.checkpoint.clone();
            attempt
                .owner
                .records
                .try_change_blocking(&attempt.id, &attempt.attempt, |stored| {
                    if attempt.control.cancel.is_cancelled() {
                        return Err(cancelled());
                    }
                    stored.task.state = TaskState::Finalizing;
                    stored.task.filename = record.filename.clone();
                    stored.reservation = Some(record.clone());
                    Ok(())
                })?;

            owned.publish().map_err(storage)?;
            attempt
                .owner
                .records
                .change_blocking(&attempt.id, &attempt.attempt, |stored| {
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
                if *attempt.control.intent.lock().unwrap() == StopIntent::Cancel {
                    owned.cleanup().map_err(storage)?;
                    attempt.owner.records.change_blocking(
                        &attempt.id,
                        &attempt.attempt,
                        |record| {
                            record.task.state = TaskState::Cancelled;
                            record.task.has_partial = false;
                            record.task.can_resume = false;
                            record.reservation = None;
                        },
                    )?;
                } else {
                    owned.retain();
                    attempt.owner.records.change_blocking(
                        &attempt.id,
                        &attempt.attempt,
                        |record| record.task.state = TaskState::Paused,
                    )?;
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
    .map_err(|error| AppError::with_source(ErrorCode::Storage, "下载发布异常终止", error))?
}

async fn transfer(
    attempt: &Attempt,
    url: &str,
    checkpoint: &ResumeCheckpoint,
    resume: bool,
    writer: &mut TransferWriter,
    progress: &mut Progress,
) -> Result<()> {
    let Some(response) = negotiate(attempt, url, checkpoint, resume, writer, progress).await?
    else {
        return Ok(());
    };

    validate_media(&response)?;
    writer
        .file
        .seek(std::io::SeekFrom::Start(progress.bytes))
        .await
        .map_err(storage)?;
    attempt.owner.records.progress(
        &attempt.id,
        &attempt.attempt,
        progress.bytes,
        progress.total,
        true,
    );

    receive_body(attempt, response, writer, progress).await
}

async fn negotiate(
    attempt: &Attempt,
    url: &str,
    checkpoint: &ResumeCheckpoint,
    resume: bool,
    writer: &TransferWriter,
    progress: &mut Progress,
) -> Result<Option<reqwest::Response>> {
    let mut request = attempt
        .owner
        .client
        .get(url)
        .header("Referer", "https://scgc.video.play/")
        .header("Accept-Encoding", "identity");
    if resume {
        request = request
            .header("Range", format!("bytes={}-", checkpoint.committed_bytes))
            .header("If-Range", checkpoint.etag.as_deref().unwrap_or(""));
    }

    let response = tokio::select! {
        biased;
        _ = attempt.control.cancel.cancelled() => return Err(cancelled()),
        result = tokio::time::timeout(attempt.owner.config.header_timeout, request.send()) => {
            result
                .map_err(|error| {
                    AppError::with_source(ErrorCode::Timeout, "视频服务响应超时", error)
                })?
                .map_err(network)?
        }
    };

    if resume {
        match decide(
            checkpoint,
            response.status(),
            response.headers(),
            writer.file.metadata().await.map_err(storage)?.len(),
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
            ResumeDecision::AlreadyComplete => return Ok(None),
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
    Ok(Some(response))
}

async fn receive_body(
    attempt: &Attempt,
    response: reqwest::Response,
    writer: &mut TransferWriter,
    progress: &mut Progress,
) -> Result<()> {
    let mut response = response;
    let mut emitted = Instant::now();
    let mut checkpointed = Instant::now();

    loop {
        let chunk = tokio::select! {
            biased;
            _ = attempt.control.cancel.cancelled() => return Err(cancelled()),
            result = response.chunk() => result.map_err(network)?,
        };
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

        writer.file.write_all(&chunk).await.map_err(storage)?;
        progress.bytes += chunk.len() as u64;

        let publish = emitted.elapsed() >= Duration::from_millis(100);
        attempt.owner.records.progress(
            &attempt.id,
            &attempt.attempt,
            progress.bytes,
            progress.total,
            publish,
        );
        if publish {
            emitted = Instant::now();
        }

        if checkpointed.elapsed() >= Duration::from_secs(1) {
            writer.file.flush().await.map_err(storage)?;
            writer.file.sync_all().await.map_err(storage)?;
            save_checkpoint(
                &attempt.owner,
                &attempt.id,
                &attempt.attempt,
                &mut writer.reservation,
                progress,
            )
            .await?;
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
    let Some(mut owned) = reservation.take() else {
        // A panicked blocking checkpoint has already dropped its durable reservation safely.
        return Err(AppError::new(
            ErrorCode::Storage,
            "下载进度保存未完成，临时文件已保留",
        ));
    };
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
        .records
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

#[cfg(test)]
mod tests {
    use std::{
        io::Write,
        pin::Pin,
        task::{Context, Poll},
    };

    use tokio::io::AsyncWrite;

    use super::*;

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
    async fn cancellation_before_publication_commit_preserves_pause_and_cleans_cancel() {
        use super::super::{
            ContentRef, DownloadTask,
            manager::{Control, DownloadManager},
            store::{DownloadDocument, StoredTask},
        };

        for intent in [StopIntent::Pause, StopIntent::Cancel] {
            let root = tempfile::tempdir().unwrap();
            let directory = super::super::files::DownloadDirectory::open(root.path()).unwrap();
            let (mut writer, mut reservation) = directory.reserve("clip.mp4").unwrap();
            reservation
                .upgrade("task".into(), "attempt".into())
                .unwrap();
            writer.write_all(b"complete").unwrap();
            drop(writer);
            let checkpoint = reservation.checkpoint(8, Some(8), None).unwrap();
            let content = ContentRef {
                programme_id: "1".into(),
                date_id: "2".into(),
                content_id: "3".into(),
            };
            let record = StoredTask {
                task: DownloadTask {
                    id: "task".into(),
                    attempt_id: "attempt".into(),
                    content: content.clone(),
                    metadata: crate::history::HistoryMetadata {
                        content,
                        programme_name: "News".into(),
                        broadcast_date: "2026-10-17".into(),
                        title: "Clip".into(),
                        cover: None,
                    },
                    filename: "clip.mp4".into(),
                    quality: crate::media::Quality::Standard,
                    state: TaskState::Running,
                    received_bytes: 8,
                    total_bytes: Some(8),
                    error: None,
                    revision: 1,
                    created_at: "2026-10-17T00:00:00.000Z".into(),
                    can_resume: false,
                    has_partial: true,
                    file_available: false,
                },
                directory: directory.path().to_owned(),
                reservation: Some(checkpoint.clone()),
                completed_identity: None,
            };
            let manager = DownloadManager::build(
                Default::default(),
                Ok(None),
                DownloadDocument {
                    version: 1,
                    revision: 1,
                    tasks: vec![record],
                },
            )
            .unwrap();
            let control = Control::new(true);
            control.stop(intent);
            let attempt = Attempt {
                owner: manager.inner.clone(),
                id: "task".into(),
                attempt: "attempt".into(),
                control,
            };

            publish(&attempt, reservation).await.unwrap();

            let task = manager.list()[0].clone();
            assert!(!root.path().join("clip.mp4").exists());
            let partial = root.path().join(format!(".sctv-dl-{}.part", checkpoint.id));
            if intent == StopIntent::Cancel {
                assert_eq!(task.state, TaskState::Cancelled);
                assert!(!partial.exists());
                assert!(!task.has_partial);
            } else {
                assert_eq!(task.state, TaskState::Paused);
                assert_eq!(std::fs::read(partial).unwrap(), b"complete");
                assert!(task.has_partial);
            }
            manager.shutdown().await;
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
