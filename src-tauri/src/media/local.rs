use std::{fs::File, io, sync::Arc};

use axum::{
    body::{Body, Bytes},
    http::{HeaderMap, HeaderValue, Method, StatusCode, request::Parts},
};
use tokio::sync::mpsc;
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use super::http::LocalReaders;
use crate::error::{AppError, ErrorCode};

const READ_CHUNK_BYTES: u64 = 64 * 1024;
const BODY_CHANNEL_CAPACITY: usize = 1;

pub(super) struct LocalSource {
    pub readers: Arc<LocalReaders>,
    pub quality: super::Quality,
    pub file: Arc<File>,
    pub length: u64,
    #[cfg(test)]
    pub read_gate: Option<Arc<ReadGate>>,
}

#[derive(Clone, Copy)]
struct ByteRange {
    offset: u64,
    length: u64,
}

struct LocalRead {
    file: Arc<File>,
    range: ByteRange,
    #[cfg(test)]
    read_gate: Option<Arc<ReadGate>>,
}

#[cfg(test)]
pub(super) struct ReadGate {
    pub started: std::sync::Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    pub release: std::sync::Mutex<std::sync::mpsc::Receiver<()>>,
}

#[cfg(test)]
impl ReadGate {
    fn wait(&self) {
        if let Some(started) = self.started.lock().unwrap().take() {
            started.send(()).unwrap();
            self.release.lock().unwrap().recv().unwrap();
        }
    }
}

impl LocalSource {
    /// Builds a local range response and registers its reader before returning a body.
    pub(super) fn response(
        &self,
        request: &Parts,
        cancellation: CancellationToken,
        producers: &TaskTracker,
    ) -> (StatusCode, HeaderMap, Body) {
        let mut headers = HeaderMap::new();
        headers.insert("content-type", HeaderValue::from_static("video/mp4"));
        headers.insert("accept-ranges", HeaderValue::from_static("bytes"));

        let requested_range = request
            .headers
            .get("range")
            .and_then(|value| value.to_str().ok());
        let Some((status, range)) = select_range(requested_range, self.length, &mut headers) else {
            return (StatusCode::RANGE_NOT_SATISFIABLE, headers, Body::empty());
        };
        headers.insert(
            "content-length",
            HeaderValue::from_str(&range.length.to_string()).unwrap(),
        );
        if request.method == Method::HEAD {
            return (status, headers, Body::empty());
        }

        let body = self.body(range, cancellation, producers);
        (status, headers, body)
    }

    fn body(
        &self,
        range: ByteRange,
        cancellation: CancellationToken,
        producers: &TaskTracker,
    ) -> Body {
        let (sender, receiver) = mpsc::channel(BODY_CHANNEL_CAPACITY);
        let stop = cancellation.clone();
        let readers = self.readers.clone();
        let read = LocalRead {
            file: self.file.clone(),
            range,
            #[cfg(test)]
            read_gate: self.read_gate.clone(),
        };
        let task_producers = readers.producers.clone();

        let producer = task_producers.spawn(async move {
            // URL removal can drop the session while a blocking read still owns the file.
            let _readers = readers;
            produce_chunks(read, stop, sender).await;
        });

        // Service shutdown also awaits local work, including sessions already closed by the UI.
        producers.spawn(async move {
            if let Err(error) = producer.await {
                AppError::with_source(ErrorCode::Storage, "本机视频读取异常终止", error)
                    .reported("finish local media producer");
            }
        });

        response_body(receiver, cancellation)
    }
}

fn select_range(
    requested: Option<&str>,
    file_length: u64,
    headers: &mut HeaderMap,
) -> Option<(StatusCode, ByteRange)> {
    let Some(requested) = requested else {
        return Some((
            StatusCode::OK,
            ByteRange {
                offset: 0,
                length: file_length,
            },
        ));
    };
    let Some((start, end)) = parse_range(requested, file_length) else {
        headers.insert(
            "content-range",
            HeaderValue::from_str(&format!("bytes */{file_length}")).unwrap(),
        );
        return None;
    };

    headers.insert(
        "content-range",
        HeaderValue::from_str(&format!("bytes {start}-{end}/{file_length}")).unwrap(),
    );
    let range = ByteRange {
        offset: start,
        length: end - start + 1,
    };
    Some((StatusCode::PARTIAL_CONTENT, range))
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

async fn produce_chunks(
    read: LocalRead,
    stop: CancellationToken,
    sender: mpsc::Sender<io::Result<Bytes>>,
) {
    let mut offset = read.range.offset;
    let mut remaining = read.range.length;

    while remaining > 0 {
        if stop.is_cancelled() || sender.is_closed() {
            return;
        }

        let count = remaining.min(READ_CHUNK_BYTES) as usize;
        let chunk = read.chunk_at(offset, count).await;

        // A disconnect or explicit close may have happened while the read was blocked.
        // Those paths stop quietly; an active stream reports a genuine failure once.
        if stop.is_cancelled() || sender.is_closed() {
            return;
        }
        let chunk = match chunk {
            Ok(bytes) => bytes,
            Err(error) => {
                let error = AppError::with_source(ErrorCode::Storage, "本机视频读取失败", error)
                    .reported("read local media chunk");
                send_chunk(&sender, Err(io::Error::other(error)), &stop).await;
                return;
            }
        };
        offset += chunk.len() as u64;
        remaining -= chunk.len() as u64;

        if !send_chunk(&sender, Ok(chunk), &stop).await {
            return;
        }
    }
}

impl LocalRead {
    async fn chunk_at(&self, offset: u64, count: usize) -> io::Result<Bytes> {
        let file = self.file.clone();
        #[cfg(test)]
        let read_gate = self.read_gate.clone();

        // A running blocking read cannot be cancelled. File deletion must await the worker.
        let worker = tokio::task::spawn_blocking(move || {
            #[cfg(test)]
            if let Some(gate) = read_gate {
                gate.wait();
            }

            read_chunk_at(&file, offset, count)
        });

        worker.await.map_err(io::Error::other)?
    }
}

fn read_chunk_at(file: &File, offset: u64, count: usize) -> io::Result<Bytes> {
    let mut bytes = vec![0; count];

    // Each Range request supplies its own offset and never uses the shared file cursor.
    #[cfg(unix)]
    let count = {
        use std::os::unix::fs::FileExt;

        file.read_at(&mut bytes, offset)?
    };
    #[cfg(windows)]
    let count = {
        use std::os::windows::fs::FileExt;

        file.seek_read(&mut bytes, offset)?
    };
    if count == 0 {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "Local video was truncated",
        ));
    }

    bytes.truncate(count);
    Ok(Bytes::from(bytes))
}

async fn send_chunk(
    sender: &mpsc::Sender<io::Result<Bytes>>,
    chunk: io::Result<Bytes>,
    cancellation: &CancellationToken,
) -> bool {
    tokio::select! {
        biased;
        _ = cancellation.cancelled() => false,
        result = sender.send(chunk) => result.is_ok(),
    }
}

fn response_body(
    receiver: mpsc::Receiver<io::Result<Bytes>>,
    cancellation: CancellationToken,
) -> Body {
    let stream = futures_util::stream::try_unfold(
        (receiver, cancellation),
        |(mut receiver, cancellation)| async move {
            let chunk = tokio::select! {
                biased;
                _ = cancellation.cancelled() => {
                    return Err(io::Error::new(io::ErrorKind::Interrupted, "Playback closed"));
                },
                item = receiver.recv() => item.transpose()?,
            };

            Ok(chunk.map(|bytes| (bytes, (receiver, cancellation))))
        },
    );

    Body::from_stream(stream)
}
