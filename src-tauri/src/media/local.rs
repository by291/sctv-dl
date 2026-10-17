use axum::{
    body::{Body, Bytes},
    http::{HeaderMap, HeaderValue, Method, StatusCode},
};
use std::{fs::File, io, sync::Arc};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

pub(super) struct LocalSource {
    pub task_id: String,
    pub quality: super::Quality,
    pub file: Arc<File>,
    pub length: u64,
}

pub(super) fn response(
    source: &LocalSource,
    method: &Method,
    request: &HeaderMap,
    cancellation: CancellationToken,
    producers: &TaskTracker,
    sessions: &TaskTracker,
) -> (StatusCode, HeaderMap, Body) {
    let mut headers = HeaderMap::new();
    headers.insert("content-type", HeaderValue::from_static("video/mp4"));
    headers.insert("accept-ranges", HeaderValue::from_static("bytes"));
    let range = request.get("range").and_then(|value| value.to_str().ok());
    let (start, end, status) = match range {
        None => (0, source.length.saturating_sub(1), StatusCode::OK),
        Some(value) => match parse_range(value, source.length) {
            Some((start, end)) => {
                headers.insert(
                    "content-range",
                    HeaderValue::from_str(&format!("bytes {start}-{end}/{}", source.length))
                        .unwrap(),
                );
                (start, end, StatusCode::PARTIAL_CONTENT)
            }
            None => {
                headers.insert(
                    "content-range",
                    HeaderValue::from_str(&format!("bytes */{}", source.length)).unwrap(),
                );
                return (StatusCode::RANGE_NOT_SATISFIABLE, headers, Body::empty());
            }
        },
    };
    let length = if source.length == 0 {
        0
    } else {
        end - start + 1
    };
    headers.insert(
        "content-length",
        HeaderValue::from_str(&length.to_string()).unwrap(),
    );
    if *method == Method::HEAD {
        return (status, headers, Body::empty());
    }
    (
        status,
        headers,
        body(
            source.file.clone(),
            start,
            length,
            cancellation,
            producers,
            sessions,
        ),
    )
}

fn parse_range(value: &str, length: u64) -> Option<(u64, u64)> {
    let (start, end) = value.strip_prefix("bytes=")?.split_once('-')?;
    if length == 0 {
        return None;
    }
    if start.is_empty() {
        let suffix: u64 = end.parse().ok()?;
        return (suffix > 0).then(|| (length.saturating_sub(suffix), length - 1));
    }
    let start: u64 = start.parse().ok()?;
    let end = if end.is_empty() {
        length - 1
    } else {
        end.parse::<u64>().ok()?.min(length - 1)
    };
    (start < length && start <= end).then_some((start, end))
}

fn body(
    file: Arc<File>,
    offset: u64,
    length: u64,
    cancellation: CancellationToken,
    producers: &TaskTracker,
    sessions: &TaskTracker,
) -> Body {
    let (sender, receiver) = tokio::sync::mpsc::channel::<io::Result<Bytes>>(1);
    let stop = cancellation.clone();
    let producer = sessions.spawn(async move {
        let mut offset = offset;
        let mut remaining = length;
        while remaining > 0 {
            if stop.is_cancelled() || sender.is_closed() { break; }
            let file = file.clone();
            let count = remaining.min(64 * 1024) as usize;
            // Positional reads give each Range request its own cursor without cloning
            // a shared file offset. A cancelled read is awaited before releasing ownership.
            let read = tokio::task::spawn_blocking(move || {
                let mut bytes = vec![0;count];
                #[cfg(unix)]
                let count = { use std::os::unix::fs::FileExt; file.read_at(&mut bytes,offset)? };
                #[cfg(windows)]
                let count = { use std::os::windows::fs::FileExt; file.seek_read(&mut bytes,offset)? };
                if count == 0 { return Err(io::Error::new(io::ErrorKind::UnexpectedEof,"Local video was truncated")); }
                bytes.truncate(count);
                Ok(Bytes::from(bytes))
            }).await.map_err(io::Error::other).and_then(|result| result);
            if let Ok(bytes) = &read { offset += bytes.len() as u64; remaining -= bytes.len() as u64; }
            let failed = read.is_err();
            tokio::select! { biased; _ = stop.cancelled() => break, result = sender.send(read) => if result.is_err() { break; } }
            if failed { break; }
        }
    });
    // The server owns each local producer as well as the task-specific session owner.
    producers.spawn(async move {
        let _ = producer.await;
    });
    Body::from_stream(futures_util::stream::try_unfold(
        (receiver, cancellation),
        |(mut receiver, cancellation)| async move {
            let item = tokio::select! { biased; _ = cancellation.cancelled() => return Err(io::Error::new(io::ErrorKind::Interrupted,"Playback closed")), item = receiver.recv() => item };
            Ok(item
                .transpose()?
                .map(|bytes| (bytes, (receiver, cancellation))))
        },
    ))
}
