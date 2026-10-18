use std::{fs::File, io, sync::Arc};

use axum::{
    body::{Body, Bytes},
    http::{HeaderMap, HeaderValue, Method, StatusCode},
};
use tokio::sync::mpsc;
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use super::http::LocalReaders;
use crate::error::{AppError, ErrorCode};

pub(super) struct LocalSource {
    pub readers: Arc<LocalReaders>,
    pub quality: super::Quality,
    pub file: Arc<File>,
    pub length: u64,
    #[cfg(test)]
    pub read_gate: Option<Arc<ReadGate>>,
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

pub(super) fn response(
    source: &LocalSource,
    method: &Method,
    request: &HeaderMap,
    cancellation: CancellationToken,
    producers: &TaskTracker,
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
            source.readers.clone(),
            #[cfg(test)]
            source.read_gate.clone(),
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
    readers: Arc<LocalReaders>,
    #[cfg(test)] read_gate: Option<Arc<ReadGate>>,
) -> Body {
    let (sender, receiver) = mpsc::channel(1);
    let stop = cancellation.clone();
    let task_producers = readers.producers.clone();
    let producer = task_producers.spawn(async move {
        // URL removal can drop the session while a blocking read still owns the file.
        // Keep its task owner reachable until the read and producer have completed.
        let _readers = readers;
        produce_chunks(
            file,
            offset,
            length,
            stop,
            sender,
            #[cfg(test)]
            read_gate,
        )
        .await;
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

async fn produce_chunks(
    file: Arc<File>,
    mut offset: u64,
    mut remaining: u64,
    stop: CancellationToken,
    sender: mpsc::Sender<io::Result<Bytes>>,
    #[cfg(test)] read_gate: Option<Arc<ReadGate>>,
) {
    while remaining > 0 {
        if stop.is_cancelled() || sender.is_closed() {
            return;
        }

        let file = file.clone();
        let count = remaining.min(64 * 1024) as usize;
        #[cfg(test)]
        let read_gate = read_gate.clone();

        // Never race cancellation against the JoinHandle: spawn_blocking cannot be
        // aborted once running, and task/file deletion must await that actual read.
        let read = tokio::task::spawn_blocking(move || {
            #[cfg(test)]
            if let Some(gate) = read_gate {
                gate.wait();
            }

            read_chunk_at(&file, offset, count)
        })
        .await
        .map_err(io::Error::other)
        .and_then(|result| result);

        // A disconnect or explicit close may have happened while the read was blocked.
        // Those paths stop quietly; an active stream reports a genuine failure once.
        if stop.is_cancelled() || sender.is_closed() {
            return;
        }
        let chunk = match read {
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

fn read_chunk_at(file: &File, offset: u64, count: usize) -> io::Result<Bytes> {
    let mut bytes = vec![0; count];

    // Positional reads preserve independent cursors for concurrent Range requests.
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
