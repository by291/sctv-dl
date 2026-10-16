use std::{
    collections::HashMap,
    net::SocketAddr,
    sync::{Arc, Mutex},
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
    pub upstream_origin: String,
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
            upstream_origin: "https://fscgc.scgchc.com/".into(),
            webview_origins,
            header_timeout: Duration::from_secs(20),
            idle_timeout: Duration::from_secs(30),
        }
    }
}

pub(super) struct Session {
    pub sources: Vec<MediaSource>,
    pub cancellation: CancellationToken,
}

pub(super) struct Inner {
    pub config: MediaConfig,
    pub origin: Url,
    pub client: Client,
    pub address: SocketAddr,
    pub sessions: Mutex<HashMap<String, Arc<Session>>>,
    pub producers: TaskTracker,
}

pub struct MediaServer {
    inner: Arc<Inner>,
    shutdown: CancellationToken,
    task: Option<JoinHandle<()>>,
}

impl MediaServer {
    // Production callers use the default fixed CDN configuration; no command accepts this configuration.
    pub async fn bind(config: MediaConfig) -> Result<Self> {
        let origin = Url::parse(&config.upstream_origin).map_err(|error| {
            AppError::with_source(ErrorCode::InvalidInput, "视频服务地址无效", error)
        })?;
        let client = Client::builder()
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
            origin,
            client,
            address,
            sessions: Mutex::new(HashMap::new()),
            producers: TaskTracker::new(),
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
            policy::target(&source.url, &self.inner.origin)?;
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
                sources,
                cancellation: CancellationToken::new(),
            }),
        );

        Ok(PlaybackSession {
            id,
            selected_quality,
            sources: output,
        })
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
