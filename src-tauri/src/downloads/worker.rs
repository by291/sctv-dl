use super::{
    TaskState,
    files::Reservation,
    manager::{Inner, Job},
};
use crate::error::{AppError, ErrorCode, Result};
use std::{
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::io::AsyncWriteExt;

pub(super) async fn run(owner: Arc<Inner>, job: Job) {
    let Job {
        id,
        url,
        reservation,
        cancel,
    } = job;
    let permit = tokio::select! {
        biased;
        _ = cancel.cancelled() => None,
        result = owner.slots.clone().acquire_owned() => result.ok(),
    };
    let file = reservation.writer().map(tokio::fs::File::from_std);
    let mut file = match file {
        Ok(file) => file,
        Err(error) => {
            let error = AppError::with_source(
                ErrorCode::Storage,
                format!("无法打开下载文件：{error}"),
                error,
            );
            let result = finalize_or_cleanup(reservation, Err(error), false).await;
            complete_task(&owner, &id, result);
            return;
        }
    };
    let result = if permit.is_none() {
        Err(AppError::new(ErrorCode::Cancelled, "下载已取消"))
    } else {
        owner.update(&id, |task| task.state = TaskState::Running);
        tokio::select! {
            biased;
            _ = cancel.cancelled() => Err(AppError::new(ErrorCode::Cancelled, "下载已取消")),
            result = transfer(&owner, &id, &url, &mut file) => result,
        }
    };
    let result = close_writer(file, result).await;
    let result = finalize_or_cleanup(reservation, result, cancel.is_cancelled()).await;
    complete_task(&owner, &id, result);
    drop(permit);
}

async fn close_writer(mut file: tokio::fs::File, result: Result<()>) -> Result<()> {
    // Pending Tokio file writes must finish and the handle must close before deletion/rename.
    let flushed = file.flush().await.map_err(storage);
    let synced = if result.is_ok() && flushed.is_ok() {
        file.sync_all().await.map_err(storage)
    } else {
        Ok(())
    };
    drop(file.into_std().await);
    result.and(flushed).and(synced)
}

async fn finalize_or_cleanup(
    reservation: Reservation,
    result: Result<()>,
    cancelled: bool,
) -> Result<String> {
    let publish = result.is_ok() && !cancelled;
    tokio::task::spawn_blocking(move || {
        if publish {
            reservation.finish().map_err(storage)
        } else {
            match (result, reservation.cleanup().map_err(storage)) {
                (_, Err(error)) => Err(error),
                (Err(error), Ok(())) => Err(error),
                (Ok(()), Ok(())) => Err(AppError::new(ErrorCode::Cancelled, "下载已取消")),
            }
        }
    })
    .await
    .map_err(|error| {
        AppError::with_source(
            ErrorCode::Storage,
            if publish {
                "保存文件异常终止"
            } else {
                "清理文件异常终止"
            },
            error,
        )
    })?
}

fn complete_task(owner: &Inner, id: &str, result: Result<String>) {
    let result = result.map_err(|error| error.reported("download task"));
    owner.update(id, |task| match result {
        Ok(filename) => {
            task.filename = filename;
            task.state = TaskState::Completed;
        }
        Err(error) if error.code == ErrorCode::Cancelled => task.state = TaskState::Cancelled,
        Err(error) => {
            task.state = TaskState::Failed;
            task.error = Some(error.message);
        }
    });
}

async fn transfer<W: tokio::io::AsyncWrite + Unpin>(
    owner: &Inner,
    id: &str,
    url: &str,
    file: &mut W,
) -> Result<()> {
    let response = tokio::time::timeout(
        owner.config.header_timeout,
        owner
            .client
            .get(url)
            .header("Referer", "https://scgc.video.play/")
            .header("Accept-Encoding", "identity")
            .send(),
    )
    .await
    .map_err(|error| AppError::with_source(ErrorCode::Timeout, "视频服务响应超时", error))?
    .map_err(network)?;
    validate_response(&response)?;

    let total = response.content_length();
    owner.update(id, |task| task.total_bytes = total);
    let mut response = response;
    let mut received = 0;
    let mut emitted = Instant::now();
    while let Some(chunk) = response.chunk().await.map_err(network)? {
        file.write_all(&chunk).await.map_err(storage)?;
        received += chunk.len() as u64;
        let publish = emitted.elapsed() >= Duration::from_millis(100);
        owner.record_progress(id, received, publish);
        if publish {
            emitted = Instant::now();
        }
    }
    file.flush().await.map_err(storage)?;
    // Every written chunk updates the snapshot; the terminal event includes the final count.
    Ok(())
}

fn validate_response(response: &reqwest::Response) -> Result<()> {
    if response.status() != 200 {
        return Err(AppError::new(
            ErrorCode::Upstream,
            format!("视频下载失败（HTTP {}）", response.status().as_u16()),
        ));
    }
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

pub(super) fn storage(error: std::io::Error) -> AppError {
    AppError::with_source(
        ErrorCode::Storage,
        format!("无法保存或清理下载文件：{error}"),
        error,
    )
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
        pin::Pin,
        task::{Context, Poll},
    };
    use tokio::io::AsyncWrite;

    struct FailedFlush;
    impl AsyncWrite for FailedFlush {
        fn poll_write(
            self: Pin<&mut Self>,
            _: &mut Context<'_>,
            buffer: &[u8],
        ) -> Poll<std::io::Result<usize>> {
            Poll::Ready(Ok(buffer.len()))
        }
        fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Ready(Err(std::io::Error::other("flush failed")))
        }
        fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Ready(Ok(()))
        }
    }

    #[tokio::test]
    async fn propagates_a_sink_flush_failure_after_receiving_the_complete_body() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let origin = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            axum::serve(
                listener,
                axum::Router::new().fallback(|| async {
                    axum::http::Response::builder()
                        .header("Content-Type", "video/mp4")
                        .body(axum::body::Body::from("fixture"))
                        .unwrap()
                }),
            )
            .await
            .unwrap();
        });
        let manager = super::super::DownloadManager::new(super::super::DownloadConfig {
            upstream_origin: origin.clone(),
            ..super::super::DownloadConfig::default()
        })
        .unwrap();
        let error = transfer(
            &manager.inner,
            "absent",
            &format!("{origin}/clip.mp4"),
            &mut FailedFlush,
        )
        .await
        .unwrap_err();
        assert_eq!(error.code, ErrorCode::Storage);
        manager.shutdown().await;
        server.abort();
    }
}
