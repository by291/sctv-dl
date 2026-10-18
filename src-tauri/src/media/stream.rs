use std::io;

use axum::body::Body;
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use crate::error::{AppError, ErrorCode};

pub(super) fn body(
    upstream: reqwest::Response,
    cancellation: CancellationToken,
    producers: &TaskTracker,
) -> Body {
    let producer_cancellation = cancellation.clone();
    let (sender, receiver) = tokio::sync::mpsc::channel(1);
    producers.spawn(async move {
        // This owner observes cancellation even while Hyper has stopped polling the body.
        let mut upstream = upstream;
        loop {
            let item = tokio::select! {
                biased;
                _ = producer_cancellation.cancelled() => break,
                _ = sender.closed() => break,
                item = upstream.chunk() => match item {
                    Ok(Some(chunk)) => Ok(chunk),
                    Ok(None) => break,
                    Err(error) => {
                        let code = if error.is_timeout() {
                            ErrorCode::Timeout
                        } else {
                            ErrorCode::Upstream
                        };
                        let error = AppError::with_source(code, "视频读取失败", error.without_url())
                            .reported("read media response body");
                        Err(io::Error::other(error))
                    },
                },
            };
            let failed = item.is_err();

            tokio::select! {
                biased;
                _ = producer_cancellation.cancelled() => break,
                result = sender.send(item) => {
                    if result.is_err() {
                        break;
                    }
                },
            }
            if failed {
                break;
            }
        }
    });

    let stream = futures_util::stream::try_unfold(
        (receiver, cancellation),
        |(mut receiver, cancellation)| async move {
            let chunk = tokio::select! {
                biased;
                _ = cancellation.cancelled() => {
                    return Err(io::Error::new(io::ErrorKind::Interrupted, "playback session closed"));
                },
                item = receiver.recv() => match item {
                    Some(chunk) => Some(chunk?),
                    None => None,
                },
            };

            Ok(chunk.map(|chunk| (chunk, (receiver, cancellation))))
        },
    );

    Body::from_stream(stream)
}
