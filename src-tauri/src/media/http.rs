use axum::{
    Router,
    body::Body,
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, Method, Request, Response, StatusCode},
    routing::any,
};
use reqwest::{Client, Url};
use std::{
    collections::HashMap,
    io,
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::{
    net::TcpListener,
    task::{JoinHandle, JoinSet},
};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use super::{MediaSource, PlaybackSession, PlaybackSource, Quality, policy};
use crate::error::{AppError, Result};

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

struct Session {
    sources: Vec<MediaSource>,
    cancellation: CancellationToken,
}
struct Inner {
    config: MediaConfig,
    origin: Url,
    client: Client,
    address: SocketAddr,
    sessions: Mutex<HashMap<String, Arc<Session>>>,
}

pub struct MediaServer {
    inner: Arc<Inner>,
    shutdown: CancellationToken,
    task: Option<JoinHandle<()>>,
}

impl MediaServer {
    // Production callers use the default fixed CDN configuration; no command accepts this configuration.
    pub async fn bind(config: MediaConfig) -> Result<Self> {
        let origin = Url::parse(&config.upstream_origin)
            .map_err(|_| AppError::new("invalid-input", "视频服务地址无效"))?;
        let client = Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .gzip(false)
            .read_timeout(config.idle_timeout)
            .build()
            .map_err(|_| AppError::new("upstream", "无法初始化视频服务"))?;
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .map_err(|_| AppError::new("upstream", "无法启动本机视频服务"))?;
        let address = listener
            .local_addr()
            .map_err(|_| AppError::new("upstream", "无法读取本机视频服务端口"))?;
        let inner = Arc::new(Inner {
            config,
            origin,
            client,
            address,
            sessions: Mutex::new(HashMap::new()),
        });
        let router = Router::new()
            .route("/media/{id}/{quality}", any(handle))
            .with_state(inner.clone());
        let shutdown = CancellationToken::new();
        let stop = shutdown.clone();
        let task = tokio::spawn(async move {
            // Own every connection so shutdown also terminates clients that never read.
            let mut connections = JoinSet::new();
            loop {
                tokio::select! {
                    biased;
                    _ = stop.cancelled() => break,
                    _ = connections.join_next(), if !connections.is_empty() => {},
                    accepted = listener.accept() => {
                        let Ok((stream, _)) = accepted else { break; };
                        let service = hyper_util::service::TowerToHyperService::new(router.clone());
                        connections.spawn(async move {
                            let _ = hyper::server::conn::http1::Builder::new()
                                .serve_connection(hyper_util::rt::TokioIo::new(stream), service)
                                .await;
                        });
                    }
                }
            }
            connections.abort_all();
            while connections.join_next().await.is_some() {}
        });
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
            return Err(AppError::new("invalid-input", "视频来源无效"));
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
        if let Some(session) = self.inner.sessions.lock().unwrap().remove(id) {
            session.cancellation.cancel();
        }
    }

    fn stop(&self) {
        self.shutdown.cancel();
        for (_, session) in self.inner.sessions.lock().unwrap().drain() {
            session.cancellation.cancel();
        }
    }

    pub async fn shutdown(mut self) {
        self.stop();
        if let Some(task) = self.task.take() {
            let _ = task.await;
        }
    }
}

impl Drop for MediaServer {
    fn drop(&mut self) {
        self.stop();
    }
}

fn response(
    status: StatusCode,
    headers: HeaderMap,
    body: Body,
    origin: Option<&HeaderValue>,
) -> Response<Body> {
    let mut response = Response::new(body);
    *response.status_mut() = status;
    *response.headers_mut() = headers;
    let headers = response.headers_mut();
    headers.insert("cache-control", HeaderValue::from_static("no-store"));
    headers.insert(
        "x-content-type-options",
        HeaderValue::from_static("nosniff"),
    );
    if let Some(origin) = origin {
        headers.insert("access-control-allow-origin", origin.clone());
        headers.insert("vary", HeaderValue::from_static("Origin"));
        headers.insert(
            "access-control-expose-headers",
            HeaderValue::from_static("Content-Length, Content-Range, Accept-Ranges"),
        );
    }
    response
}

async fn handle(
    State(inner): State<Arc<Inner>>,
    Path((id, quality)): Path<(String, String)>,
    request: Request<Body>,
) -> Response<Body> {
    let headers = request.headers();
    let origin = headers.get("origin");
    if headers.get("host").and_then(|host| host.to_str().ok())
        != Some(inner.address.to_string().as_str())
        || origin.is_some_and(|value| {
            !inner
                .config
                .webview_origins
                .iter()
                .any(|allowed| value.as_bytes() == allowed.as_bytes())
        })
    {
        return response(StatusCode::FORBIDDEN, HeaderMap::new(), Body::empty(), None);
    }
    let empty = |status| response(status, HeaderMap::new(), Body::empty(), origin);
    if ![Method::GET, Method::HEAD, Method::OPTIONS].contains(request.method()) {
        return empty(StatusCode::METHOD_NOT_ALLOWED);
    }
    let session = { inner.sessions.lock().unwrap().get(&id).cloned() };
    let Some(session) = session else {
        return empty(StatusCode::NOT_FOUND);
    };
    let Some(source) = session
        .sources
        .iter()
        .find(|source| source.quality.as_str() == quality)
    else {
        return empty(StatusCode::NOT_FOUND);
    };
    if request.method() == Method::OPTIONS {
        let mut headers = HeaderMap::new();
        headers.insert(
            "access-control-allow-methods",
            HeaderValue::from_static("GET, HEAD, OPTIONS"),
        );
        headers.insert(
            "access-control-allow-headers",
            HeaderValue::from_static("Range, If-Range"),
        );
        return response(StatusCode::NO_CONTENT, headers, Body::empty(), origin);
    }
    let mut upstream = inner
        .client
        .request(request.method().clone(), &source.url)
        .header("Referer", "https://scgc.video.play/")
        .header("Accept-Encoding", "identity");
    for name in ["range", "if-range"] {
        if let Some(value) = headers.get(name) {
            upstream = upstream.header(name, value);
        }
    }
    let upstream = tokio::select! {
        biased;
        _ = session.cancellation.cancelled() => return empty(StatusCode::GONE),
        result = tokio::time::timeout(inner.config.header_timeout, upstream.send()) => match result {
            Ok(Ok(response)) => response,
            Ok(Err(error)) if error.is_timeout() => return empty(StatusCode::GATEWAY_TIMEOUT),
            Err(_) => return empty(StatusCode::GATEWAY_TIMEOUT),
            _ => return empty(StatusCode::BAD_GATEWAY),
        }
    };
    let status = upstream.status();
    if status.is_redirection() {
        return empty(StatusCode::BAD_GATEWAY);
    }
    let mut copied = HeaderMap::new();
    if !status.is_success() {
        if status == StatusCode::RANGE_NOT_SATISFIABLE
            && let Some(value) = upstream.headers().get("content-range")
        {
            copied.insert("content-range", value.clone());
        }
        return response(status, copied, Body::empty(), origin);
    }
    let content_type = upstream
        .headers()
        .get("content-type")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("")
        .split(';')
        .next()
        .unwrap_or("")
        .trim();
    if !content_type.eq_ignore_ascii_case("video/mp4")
        && !content_type.eq_ignore_ascii_case("application/octet-stream")
    {
        return empty(StatusCode::BAD_GATEWAY);
    }
    if upstream
        .headers()
        .get("content-encoding")
        .is_some_and(|value| value != "identity")
    {
        return empty(StatusCode::BAD_GATEWAY);
    }
    for name in [
        "content-type",
        "content-length",
        "content-range",
        "accept-ranges",
        "etag",
        "last-modified",
    ] {
        if let Some(value) = upstream.headers().get(name) {
            copied.insert(name, value.clone());
        }
    }
    if request.method() == Method::HEAD {
        return response(status, copied, Body::empty(), origin);
    }
    let cancellation = session.cancellation.clone();
    let producer_cancellation = cancellation.clone();
    let (sender, receiver) = tokio::sync::mpsc::channel(1);
    tokio::spawn(async move {
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
                    Err(error) => Err(io::Error::other(error)),
                },
            };
            let failed = item.is_err();
            tokio::select! {
                biased;
                _ = producer_cancellation.cancelled() => break,
                result = sender.send(item) => if result.is_err() { break; },
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
                _ = cancellation.cancelled() => return Err(io::Error::new(io::ErrorKind::Interrupted, "playback session closed")),
                item = receiver.recv() => match item {
                    Some(chunk) => Some(chunk?),
                    None => None,
                },
            };
            Ok(chunk.map(|chunk| (chunk, (receiver, cancellation))))
        },
    );
    response(status, copied, Body::from_stream(stream), origin)
}
