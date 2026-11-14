use std::sync::Arc;

use axum::{
    body::Body,
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, Method, Request, Response, StatusCode, request::Parts},
};

use super::{
    MediaSource,
    http::{Inner, Session, SessionSource},
    local::LocalSource,
    stream,
};
use crate::error::{AppError, ErrorCode};

/// Routes one authorized loopback request to its published playback source.
pub(super) async fn handle(
    State(inner): State<Arc<Inner>>,
    Path((id, quality)): Path<(String, String)>,
    request: Request<Body>,
) -> Response<Body> {
    let (request, _) = request.into_parts();
    let headers = &request.headers;
    if !allows_request(headers, &inner) {
        return response(StatusCode::FORBIDDEN, HeaderMap::new(), Body::empty(), None);
    }

    let origin = headers.get("origin");
    let empty = |status| response(status, HeaderMap::new(), Body::empty(), origin);
    if ![Method::GET, Method::HEAD, Method::OPTIONS].contains(&request.method) {
        return empty(StatusCode::METHOD_NOT_ALLOWED);
    }

    let session = { inner.sessions.lock().unwrap().get(&id).cloned() };
    let Some(session) = session else {
        return empty(StatusCode::NOT_FOUND);
    };

    if request.method == Method::OPTIONS {
        return response(
            StatusCode::NO_CONTENT,
            preflight_headers(),
            Body::empty(),
            origin,
        );
    }

    let sources = match &session.source {
        SessionSource::Upstream(sources) => sources,
        SessionSource::Local(source) => {
            if source.quality.as_str() != quality {
                return empty(StatusCode::NOT_FOUND);
            }

            return serve_local(LocalRequest {
                inner: &inner,
                source,
                session: &session,
                id: &id,
                request: &request,
            });
        }
    };
    let Some(source) = sources
        .iter()
        .find(|source| source.quality.as_str() == quality)
    else {
        return empty(StatusCode::NOT_FOUND);
    };

    let upstream = match request_upstream(&inner, &session, source, &request).await {
        Ok(upstream) => upstream,
        Err(status) => return empty(status),
    };

    let status = upstream.status();
    if status.is_redirection() {
        return empty(StatusCode::BAD_GATEWAY);
    }
    if !status.is_success() {
        return response(status, error_headers(&upstream), Body::empty(), origin);
    }

    let copied = match media_headers(&upstream) {
        Ok(headers) => headers,
        Err(status) => return empty(status),
    };
    if request.method == Method::HEAD {
        return response(status, copied, Body::empty(), origin);
    }

    let body = stream::body(upstream, session.cancellation.clone(), &inner.producers);
    response(status, copied, body, origin)
}

struct LocalRequest<'a> {
    inner: &'a Inner,
    source: &'a LocalSource,
    session: &'a Session,
    id: &'a str,
    request: &'a Parts,
}

fn serve_local(local: LocalRequest<'_>) -> Response<Body> {
    let origin = local.request.headers.get("origin");

    // Serialize local producer registration with session removal so deletion awaits every read.
    let (status, headers, body) = {
        let sessions = local.inner.sessions.lock().unwrap();
        if !sessions.contains_key(local.id) {
            return response(StatusCode::GONE, HeaderMap::new(), Body::empty(), origin);
        }

        local.source.response(
            local.request,
            local.session.cancellation.clone(),
            &local.inner.producers,
        )
    };

    response(status, headers, body, origin)
}

fn allows_request(headers: &HeaderMap, inner: &Inner) -> bool {
    let expected_host = inner.address.to_string();
    let valid_host =
        headers.get("host").and_then(|host| host.to_str().ok()) == Some(expected_host.as_str());
    let valid_origin = headers.get("origin").is_none_or(|value| {
        inner
            .config
            .webview_origins
            .iter()
            .any(|allowed| value.as_bytes() == allowed.as_bytes())
    });

    valid_host && valid_origin
}

async fn request_upstream(
    inner: &Inner,
    session: &Session,
    source: &MediaSource,
    request: &Parts,
) -> std::result::Result<reqwest::Response, StatusCode> {
    let mut upstream = inner.client.request(request.method.clone(), &source.url);
    upstream = upstream
        .header("Referer", "https://scgc.video.play/")
        .header("Accept-Encoding", "identity");
    for name in ["range", "if-range"] {
        if let Some(value) = request.headers.get(name) {
            upstream = upstream.header(name, value);
        }
    }

    // A revoked session takes precedence if its header request completes at the same time.
    let pending = tokio::time::timeout(inner.config.header_timeout, upstream.send());
    let result = tokio::select! {
        biased;
        _ = session.cancellation.cancelled() => return Err(StatusCode::GONE),
        result = pending => result,
    };

    match result {
        Ok(Ok(response)) => Ok(response),
        Ok(Err(error)) => Err(upstream_header_error(error)),
        Err(error) => {
            AppError::with_source(ErrorCode::Timeout, "视频服务响应超时", error)
                .reported("request media response headers");
            Err(StatusCode::GATEWAY_TIMEOUT)
        }
    }
}

fn upstream_header_error(error: reqwest::Error) -> StatusCode {
    let (code, status) = if error.is_timeout() {
        (ErrorCode::Timeout, StatusCode::GATEWAY_TIMEOUT)
    } else {
        (ErrorCode::Upstream, StatusCode::BAD_GATEWAY)
    };

    AppError::with_source(code, "视频服务请求失败", error.without_url())
        .reported("request media response headers");
    status
}

fn error_headers(upstream: &reqwest::Response) -> HeaderMap {
    let mut headers = HeaderMap::new();
    if upstream.status() == StatusCode::RANGE_NOT_SATISFIABLE
        && let Some(value) = upstream.headers().get("content-range")
    {
        headers.insert("content-range", value.clone());
    }

    headers
}

fn media_headers(upstream: &reqwest::Response) -> std::result::Result<HeaderMap, StatusCode> {
    let upstream_headers = upstream.headers();
    let raw_content_type = upstream_headers
        .get("content-type")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("");
    let media_type = raw_content_type.split(';').next().unwrap_or("");
    let content_type = media_type.trim();
    let is_media_type = content_type.eq_ignore_ascii_case("video/mp4")
        || content_type.eq_ignore_ascii_case("application/octet-stream");
    let is_encoded = upstream_headers
        .get("content-encoding")
        .is_some_and(|value| value != "identity");

    // Forwarded byte offsets describe the identity representation.
    if !is_media_type || is_encoded {
        return Err(StatusCode::BAD_GATEWAY);
    }

    let mut headers = HeaderMap::new();
    for name in [
        "content-type",
        "content-length",
        "content-range",
        "accept-ranges",
        "etag",
        "last-modified",
    ] {
        if let Some(value) = upstream_headers.get(name) {
            headers.insert(name, value.clone());
        }
    }

    Ok(headers)
}

fn preflight_headers() -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(
        "access-control-allow-methods",
        HeaderValue::from_static("GET, HEAD, OPTIONS"),
    );
    headers.insert(
        "access-control-allow-headers",
        HeaderValue::from_static("Range, If-Range"),
    );

    headers
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
