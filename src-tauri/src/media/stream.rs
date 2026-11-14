use std::io;

use axum::body::Body;
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use crate::error::{AppError, ErrorCode};

const BODY_CHANNEL_CAPACITY: usize = 1;

/// Streams media with backpressure while keeping cancellation independent of body polling.
pub(super) fn body(
    upstream: reqwest::Response,
    cancellation: CancellationToken,
    producers: &TaskTracker,
) -> Body {
    let producer_cancellation = cancellation.clone();
    let (sender, receiver) = tokio::sync::mpsc::channel(BODY_CHANNEL_CAPACITY);
    producers.spawn(async move {
        // This owner observes cancellation even while Hyper has stopped polling the body.
        let mut upstream = upstream;
        loop {
            let chunk = tokio::select! {
                biased;
                _ = producer_cancellation.cancelled() => break,
                _ = sender.closed() => break,
                chunk = upstream.chunk() => chunk,
            };
            let item = match chunk {
                Ok(Some(chunk)) => Ok(chunk),
                Ok(None) => break,
                Err(error) => Err(read_error(error)),
            };
            let has_failed = item.is_err();

            let sent = tokio::select! {
                biased;
                _ = producer_cancellation.cancelled() => break,
                result = sender.send(item) => result,
            };
            if has_failed || sent.is_err() {
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
                    let error = io::Error::new(io::ErrorKind::Interrupted, "Playback session closed");
                    return Err(error);
                },
                item = receiver.recv() => item.transpose()?,
            };

            Ok(chunk.map(|chunk| (chunk, (receiver, cancellation))))
        },
    );

    Body::from_stream(stream)
}

fn read_error(error: reqwest::Error) -> io::Error {
    let code = if error.is_timeout() {
        ErrorCode::Timeout
    } else {
        ErrorCode::Upstream
    };
    let error = AppError::with_source(code, "视频读取失败", error.without_url())
        .reported("read media response body");

    io::Error::other(error)
}
