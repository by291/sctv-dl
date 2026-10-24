use std::{
    collections::HashMap,
    net::SocketAddr,
    sync::{Arc, Mutex, Weak},
    time::Duration,
};

use axum::{Router, routing::any};
use reqwest::{Client, Url};
use tokio::{
    net::TcpListener,
    task::{JoinHandle, JoinSet},
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use uuid::Uuid;

use super::{MediaSource, PlaybackSession, PlaybackSource, Quality, handler, policy};
use crate::error::{AppError, ErrorCode, Result};

pub struct MediaConfig {
    pub upstream_origins: Vec<String>,
    pub webview_origins: Vec<String>,
    pub header_timeout: Duration,
    pub idle_timeout: Duration,
}

impl Default for MediaConfig {
    fn default() -> Self {
        let mut webview_origins = vec!["tauri://localhost".into(), "http://tauri.localhost".into()];
        if cfg!(debug_assertions) {
            webview_origins.push("http://127.0.0.1:5180".into());
        }

        Self {
            upstream_origins: policy::default_origins(),
            webview_origins,
            header_timeout: Duration::from_secs(20),
            idle_timeout: Duration::from_secs(30),
        }
    }
}

pub(super) enum SessionSource {
    Upstream(Vec<MediaSource>),
    Local(super::local::LocalSource),
}

pub(super) struct Session {
    pub source: SessionSource,
    pub cancellation: CancellationToken,
}

type LocalReaderRegistry = Arc<Mutex<HashMap<String, Weak<LocalReaders>>>>;

pub(super) struct LocalReaders {
    pub task_id: String,
    pub producers: TaskTracker,
    registry: LocalReaderRegistry,
}

impl Drop for LocalReaders {
    fn drop(&mut self) {
        let mut registry = self.registry.lock().unwrap();
        if registry
            .get(&self.task_id)
            .is_some_and(|owner| std::ptr::eq(owner.as_ptr(), self))
        {
            // Only the final session/producer releases this owner. A new owner can be
            // opened while this final drop waits for the lock; preserve that owner.
            registry.remove(&self.task_id);
        }
    }
}

pub(super) struct Inner {
    pub config: MediaConfig,
    pub origins: Vec<Url>,
    pub client: Client,
    pub address: SocketAddr,
    pub sessions: Mutex<HashMap<String, Arc<Session>>>,
    pub producers: TaskTracker,
    local_readers: LocalReaderRegistry,
}

pub struct MediaServer {
    inner: Arc<Inner>,
    shutdown: CancellationToken,
    task: Option<JoinHandle<()>>,
}

impl MediaServer {
    // Production callers use the default fixed CDN configuration; no command accepts this configuration.
    pub async fn bind(config: MediaConfig) -> Result<Self> {
        let origins = policy::parse_origins(&config.upstream_origins)?;
        let client = Client::builder()
            .user_agent(crate::upstream::USER_AGENT)
            .redirect(reqwest::redirect::Policy::none())
            .gzip(false)
            .read_timeout(config.idle_timeout)
            .build()
            .map_err(|error| {
                AppError::with_source(
                    ErrorCode::Upstream,
                    "无法初始化视频服务",
                    error.without_url(),
                )
                .reported("initialize media HTTP client")
            })?;

        let listener = TcpListener::bind("127.0.0.1:0").await.map_err(|error| {
            AppError::with_source(ErrorCode::Upstream, "无法启动本机视频服务", error)
                .reported("bind media listener")
        })?;
        let address = listener.local_addr().map_err(|error| {
            AppError::with_source(ErrorCode::Upstream, "无法读取本机视频服务端口", error)
                .reported("read media listener address")
        })?;

        let inner = Arc::new(Inner {
            config,
            origins,
            client,
            address,
            sessions: Mutex::new(HashMap::new()),
            producers: TaskTracker::new(),
            local_readers: Arc::default(),
        });
        let router = Router::new()
            .route("/media/{id}/{quality}", any(handler::handle))
            .with_state(inner.clone());
        let shutdown = CancellationToken::new();
        let task = tokio::spawn(serve_connections(listener, router, shutdown.clone()));

        Ok(Self {
            inner,
            shutdown,
            task: Some(task),
        })
    }

    pub fn open(
        &self,
        sources: Vec<MediaSource>,
        selected_quality: Quality,
    ) -> Result<PlaybackSession> {
        if sources.is_empty()
            || sources.len() > 2
            || !sources
                .iter()
                .any(|source| source.quality == selected_quality)
            || (sources.len() == 2 && sources[0].quality == sources[1].quality)
        {
            return Err(AppError::new(ErrorCode::InvalidInput, "视频来源无效"));
        }
        for source in &sources {
            policy::target(&source.url, &self.inner.origins)?;
        }

        let id = Uuid::new_v4().to_string();
        let output = sources
            .iter()
            .map(|source| PlaybackSource {
                quality: source.quality,
                url: format!(
                    "http://{}/media/{id}/{}",
                    self.inner.address,
                    source.quality.as_str()
                ),
            })
            .collect();

        self.inner.sessions.lock().unwrap().insert(
            id.clone(),
            Arc::new(Session {
                source: SessionSource::Upstream(sources),
                cancellation: CancellationToken::new(),
            }),
        );

        Ok(PlaybackSession {
            id,
            selected_quality,
            sources: output,
        })
    }

    pub fn open_local(
        &self,
        task_id: String,
        quality: Quality,
        file: std::fs::File,
    ) -> Result<PlaybackSession> {
        let length = file
            .metadata()
            .map_err(|error| AppError::with_source(ErrorCode::Storage, "无法读取本机视频", error))?
            .len();
        let id = Uuid::new_v4().to_string();

        // Session publication and task-owner registration share the admission lock
        // used by the handler and close_task. No producer can escape a task close.
        {
            let mut sessions = self.inner.sessions.lock().unwrap();
            let readers = {
                let mut registry = self.inner.local_readers.lock().unwrap();
                if let Some(readers) = registry.get(&task_id).and_then(Weak::upgrade) {
                    readers
                } else {
                    let readers = Arc::new(LocalReaders {
                        task_id: task_id.clone(),
                        producers: TaskTracker::new(),
                        registry: self.inner.local_readers.clone(),
                    });
                    registry.insert(task_id, Arc::downgrade(&readers));
                    readers
                }
            };

            sessions.insert(
                id.clone(),
                Arc::new(Session {
                    source: SessionSource::Local(super::local::LocalSource {
                        readers,
                        quality,
                        file: Arc::new(file),
                        length,
                        #[cfg(test)]
                        read_gate: None,
                    }),
                    cancellation: CancellationToken::new(),
                }),
            );
        }

        Ok(PlaybackSession {
            sources: vec![PlaybackSource {
                quality,
                url: format!(
                    "http://{}/media/{id}/{}",
                    self.inner.address,
                    quality.as_str()
                ),
            }],
            selected_quality: quality,
            id,
        })
    }

    /// Revokes task URLs and returns completion owners, including readers from URLs
    /// already closed. Callers must await these before deleting the verified file.
    pub fn close_task(&self, task_id: &str) -> Vec<TaskTracker> {
        let mut sessions = self.inner.sessions.lock().unwrap();
        let readers = {
            self.inner
                .local_readers
                .lock()
                .unwrap()
                .get(task_id)
                .and_then(Weak::upgrade)
        };
        let ids: Vec<_> = sessions
            .iter()
            .filter_map(|(id, session)| {
                matches!(&session.source, SessionSource::Local(source) if source.readers.task_id == task_id)
                    .then_some(id.clone())
            })
            .collect();

        for id in ids {
            if let Some(session) = sessions.remove(&id) {
                session.cancellation.cancel();
            }
        }

        readers
            .map(|readers| {
                readers.producers.close();
                readers.producers.clone()
            })
            .into_iter()
            .collect()
    }

    pub fn close(&self, id: &str) {
        let session = { self.inner.sessions.lock().unwrap().remove(id) };
        if let Some(session) = session {
            session.cancellation.cancel();
        }
    }

    fn stop(&self) {
        self.shutdown.cancel();

        let sessions = {
            self.inner
                .sessions
                .lock()
                .unwrap()
                .drain()
                .map(|(_, session)| session)
                .collect::<Vec<_>>()
        };
        for session in sessions {
            session.cancellation.cancel();
        }
    }

    /// Stops admission, cancels sessions, and returns after all owned HTTP work has ended.
    pub async fn shutdown(mut self) {
        self.stop();

        if let Some(task) = self.task.take()
            && let Err(error) = task.await
        {
            AppError::with_source(ErrorCode::Upstream, "视频服务异常终止", error)
                .reported("stop media listener");
        }

        // Connections can no longer register producers; wait until their responses are dropped.
        self.inner.producers.close();
        self.inner.producers.wait().await;
    }
}

impl Drop for MediaServer {
    fn drop(&mut self) {
        // Explicit shutdown awaits ownership; Drop can only request best-effort cancellation.
        self.stop();
    }
}

async fn serve_connections(listener: TcpListener, router: Router, stop: CancellationToken) {
    // Own every connection so shutdown also terminates clients that never read.
    let mut connections = JoinSet::new();
    loop {
        tokio::select! {
            biased;
            _ = stop.cancelled() => break,
            completed = connections.join_next(), if !connections.is_empty() => {
                if let Some(Err(error)) = completed {
                    AppError::with_source(ErrorCode::Upstream, "视频连接异常终止", error)
                        .reported("serve media connection");
                }
            },
            accepted = listener.accept() => {
                let (stream, _) = match accepted {
                    Ok(connection) => connection,
                    Err(error) => {
                        AppError::with_source(ErrorCode::Upstream, "本机视频服务连接失败", error)
                            .reported("accept media connection");
                        break;
                    }
                };
                let service = hyper_util::service::TowerToHyperService::new(router.clone());
                connections.spawn(async move {
                    // Malformed requests and disconnected clients end only their own connection.
                    let _ = hyper::server::conn::http1::Builder::new()
                        .serve_connection(hyper_util::rt::TokioIo::new(stream), service)
                        .await;
                });
            }
        }
    }

    connections.abort_all();
    while connections.join_next().await.is_some() {}
}

#[cfg(test)]
mod tests {
    use std::{
        io,
        pin::Pin,
        sync::atomic::{AtomicBool, Ordering},
        task::{Context, Poll},
    };

    use axum::body::{Bytes, HttpBody};
    use futures_util::StreamExt;
    use hyper::body::Frame;

    use super::*;

    struct OwnedUpstreamBody(Arc<AtomicBool>);

    impl HttpBody for OwnedUpstreamBody {
        type Data = Bytes;
        type Error = io::Error;

        fn poll_frame(
            self: Pin<&mut Self>,
            _context: &mut Context<'_>,
        ) -> Poll<Option<std::result::Result<Frame<Bytes>, io::Error>>> {
            Poll::Pending
        }
    }

    impl Drop for OwnedUpstreamBody {
        fn drop(&mut self) {
            self.0.store(false, Ordering::SeqCst);
        }
    }

    #[tokio::test]
    async fn closed_local_session_keeps_task_and_shutdown_waiting_for_blocked_read() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("clip.mp4");
        std::fs::write(&path, b"local bytes").unwrap();
        let mut server = MediaServer::bind(MediaConfig::default()).await.unwrap();
        let session = server
            .open_local(
                "task".into(),
                Quality::Standard,
                std::fs::File::open(path).unwrap(),
            )
            .unwrap();
        let (started, reading) = tokio::sync::oneshot::channel();
        let (release, blocked) = std::sync::mpsc::channel();
        let file = {
            let mut sessions = server.inner.sessions.lock().unwrap();
            let owned = Arc::get_mut(sessions.get_mut(&session.id).unwrap()).unwrap();
            let SessionSource::Local(source) = &mut owned.source else {
                panic!("expected local source");
            };
            source.read_gate = Some(Arc::new(super::super::local::ReadGate {
                started: Mutex::new(Some(started)),
                release: Mutex::new(blocked),
            }));
            Arc::downgrade(&source.file)
        };

        let response = handler::handle(
            axum::extract::State(server.inner.clone()),
            axum::extract::Path((session.id.clone(), "standard".into())),
            axum::http::Request::builder()
                .header("host", server.inner.address.to_string())
                .body(axum::body::Body::empty())
                .unwrap(),
        )
        .await;
        assert_eq!(response.status(), axum::http::StatusCode::OK);
        reading.await.unwrap();

        server.close(&session.id);
        let trackers = server.close_task("task");
        let mut task_completion = Box::pin(async move {
            for tracker in trackers {
                tracker.wait().await;
            }
        });
        let task_waited = futures_util::poll!(&mut task_completion).is_pending();
        drop(task_completion);

        // A caller cancelling its wait must not lose ownership for a later deletion.
        let trackers = server.close_task("task");
        let mut retried_completion = Box::pin(async move {
            for tracker in trackers {
                tracker.wait().await;
            }
        });
        let retry_waited = futures_util::poll!(&mut retried_completion).is_pending();

        server.shutdown.cancel();
        server.task.take().unwrap().await.unwrap();
        let inner = server.inner.clone();
        let shutdown = server.shutdown();
        tokio::pin!(shutdown);
        let shutdown_waited = futures_util::poll!(&mut shutdown).is_pending();

        // Always release the worker before asserting, including on the broken implementation.
        release.send(()).unwrap();
        if retry_waited {
            retried_completion.await;
        }
        if shutdown_waited {
            shutdown.await;
        }
        drop(response);

        assert!(
            task_waited,
            "task close returned while its retired local read was blocked"
        );
        assert!(retry_waited, "a later task close lost its retiring reader");
        assert!(
            shutdown_waited,
            "shutdown returned while its local read was blocked"
        );
        assert!(
            file.upgrade().is_none(),
            "retired reader kept its file open"
        );
        assert!(inner.local_readers.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn truncated_local_stream_yields_one_private_read_error_then_completes() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("private-clip.mp4");
        std::fs::write(&path, b"0123456789").unwrap();
        let server = MediaServer::bind(MediaConfig::default()).await.unwrap();
        let session = server
            .open_local(
                "task".into(),
                Quality::Standard,
                std::fs::File::open(&path).unwrap(),
            )
            .unwrap();
        std::fs::OpenOptions::new()
            .write(true)
            .open(&path)
            .unwrap()
            .set_len(3)
            .unwrap();

        let response = handler::handle(
            axum::extract::State(server.inner.clone()),
            axum::extract::Path((session.id.clone(), "standard".into())),
            axum::http::Request::builder()
                .header("host", server.inner.address.to_string())
                .body(axum::body::Body::empty())
                .unwrap(),
        )
        .await;
        assert_eq!(response.status(), axum::http::StatusCode::OK);
        assert_eq!(response.headers()["content-length"], "10");
        let mut stream = response.into_body().into_data_stream();
        assert_eq!(stream.next().await.unwrap().unwrap(), "012");
        let error = stream.next().await.unwrap().unwrap_err();

        assert!(
            !error.to_string().contains("private-clip.mp4"),
            "stream diagnostics exposed the local filename"
        );
        let mut cause = std::error::Error::source(&error);
        let mut retained_truncation = false;
        while let Some(error) = cause {
            retained_truncation |= error
                .downcast_ref::<io::Error>()
                .is_some_and(|error| error.kind() == io::ErrorKind::UnexpectedEof);
            cause = error.source();
        }
        assert!(
            retained_truncation,
            "stream error lost its private I/O cause"
        );
        assert!(stream.next().await.is_none());

        server.close(&session.id);
        let inner = server.inner.clone();
        server.shutdown().await;
        assert!(inner.local_readers.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn shutdown_drains_owned_producers_before_returning() {
        let mut server = MediaServer::bind(MediaConfig::default()).await.unwrap();
        let session = server
            .open(
                vec![MediaSource {
                    quality: Quality::Standard,
                    url: "https://fscgc.scgchc.com/clip.mp4".into(),
                }],
                Quality::Standard,
            )
            .unwrap();
        let cancellation = server.inner.sessions.lock().unwrap()[&session.id]
            .cancellation
            .clone();
        let upstream_alive = Arc::new(AtomicBool::new(true));
        let upstream = reqwest::Response::from(axum::http::Response::new(reqwest::Body::wrap(
            OwnedUpstreamBody(upstream_alive.clone()),
        )));
        let _downstream =
            crate::media::stream::body(upstream, cancellation, &server.inner.producers);

        // Listener completion alone does not release a separately owned producer response.
        server.shutdown.cancel();
        server.task.take().unwrap().await.unwrap();
        assert!(upstream_alive.load(Ordering::SeqCst));

        server.shutdown().await;

        assert!(
            !upstream_alive.load(Ordering::SeqCst),
            "shutdown returned before its upstream producer released the response"
        );
    }
}
