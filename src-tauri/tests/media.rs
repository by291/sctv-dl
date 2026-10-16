mod support;

use support::{Stub, serve};

use axum::{
    Router,
    body::Body,
    http::{HeaderMap, Request, Response},
};
use sctv_dl_desktop_lib::media::{MediaConfig, MediaServer, MediaSource, Quality};
use serde_json::Value;
use std::{
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

async fn media(stub: &Stub) -> MediaServer {
    MediaServer::bind(MediaConfig {
        upstream_origin: stub.origin.clone(),
        ..MediaConfig::default()
    })
    .await
    .unwrap()
}
fn source(stub: &Stub) -> MediaSource {
    MediaSource {
        quality: Quality::Standard,
        url: format!("{}/clip.mp4", stub.origin),
    }
}
fn range_reply(headers: &HeaderMap, head: bool) -> Response<Body> {
    let bytes: Vec<u8> = (0..200).collect();
    let range = headers.get("range").and_then(|value| value.to_str().ok());
    let parsed = match range {
        None => Some((0, 199)),
        Some("bytes=0-1023") => Some((0, 199)),
        Some("bytes=30-") => Some((30, 199)),
        Some("bytes=-8") => Some((192, 199)),
        Some("bytes=0-7") => Some((0, 7)),
        _ => None,
    };
    match parsed {
        None => Response::builder()
            .status(416)
            .header("Content-Range", "bytes */200")
            .body(Body::empty())
            .unwrap(),
        Some((start, end)) => {
            let mut response = Response::builder()
                .status(if range.is_some() { 206 } else { 200 })
                .header("Content-Type", "video/mp4")
                .header("Accept-Ranges", "bytes")
                .header("Content-Length", end - start + 1);
            if range.is_some() {
                response = response.header("Content-Range", format!("bytes {start}-{end}/200"));
            }
            response
                .body(if head {
                    Body::empty()
                } else {
                    Body::from(bytes[start..=end].to_vec())
                })
                .unwrap()
        }
    }
}

#[tokio::test]
async fn enforces_the_shared_media_target_policy_before_creating_sessions() {
    let server = MediaServer::bind(MediaConfig::default()).await.unwrap();
    let fixtures: Vec<Value> =
        serde_json::from_str(include_str!("../../shared/fixtures/media-policy.json")).unwrap();
    for fixture in fixtures {
        let result = server.open(
            vec![MediaSource {
                quality: Quality::Standard,
                url: fixture["url"].as_str().unwrap().into(),
            }],
            Quality::Standard,
        );
        assert_eq!(
            result.is_ok(),
            fixture["allowed"].as_bool().unwrap(),
            "{}",
            fixture["url"]
        );
    }
    assert!(server.open(vec![], Quality::Standard).is_err());
}

#[tokio::test]
async fn streams_head_full_and_single_range_shapes_with_media_only_headers() {
    let seen = Arc::new(std::sync::Mutex::new(Vec::new()));
    let captured = seen.clone();
    let stub = serve(Router::new().fallback(move |request: Request<Body>| {
        captured.lock().unwrap().push(request.headers().clone());
        async move { range_reply(request.headers(), request.method() == "HEAD") }
    }))
    .await;
    let server = media(&stub).await;
    let session = server.open(vec![source(&stub)], Quality::Standard).unwrap();
    let url = &session.sources[0].url;
    let client = reqwest::Client::new();
    let head = client.head(url).send().await.unwrap();
    assert_eq!(head.status(), 200);
    assert_eq!(head.headers()["content-length"], "200");
    assert!(head.bytes().await.unwrap().is_empty());
    for (range, status, expected) in [
        (None, 200, (0_u8..200).collect::<Vec<_>>()),
        (Some("bytes=0-1023"), 206, (0_u8..200).collect()),
        (Some("bytes=30-"), 206, (30_u8..200).collect()),
        (Some("bytes=-8"), 206, (192_u8..200).collect()),
        (Some("bytes=0-7"), 206, (0_u8..8).collect()),
    ] {
        let mut request = client
            .get(url)
            .header("Origin", "tauri://localhost")
            .header("Cookie", "private=ignored")
            .header("Authorization", "ignored")
            .header("deviceId", "ignored");
        if let Some(range) = range {
            request = request
                .header("Range", range)
                .header("If-Range", "\"fixture\"");
        }
        let response = request.send().await.unwrap();
        assert_eq!(response.status(), status);
        assert_eq!(
            response.headers()["access-control-allow-origin"],
            "tauri://localhost"
        );
        assert_eq!(response.bytes().await.unwrap().as_ref(), expected);
    }
    let invalid = client
        .get(url)
        .header("Range", "bytes=999-")
        .send()
        .await
        .unwrap();
    assert_eq!(invalid.status(), 416);
    assert_eq!(invalid.headers()["content-range"], "bytes */200");
    for headers in seen.lock().unwrap().iter() {
        assert_eq!(headers["referer"], "https://scgc.video.play/");
        assert_eq!(headers["accept-encoding"], "identity");
        assert!(!headers.contains_key("deviceid"));
        assert!(!headers.contains_key("cookie"));
        assert!(!headers.contains_key("authorization"));
        if headers.contains_key("range") && headers["range"] != "bytes=999-" {
            assert_eq!(headers["if-range"], "\"fixture\"");
        }
    }
}

#[tokio::test]
async fn rejects_unknown_tokens_remote_origins_rebound_hosts_and_unsupported_methods() {
    let calls = Arc::new(AtomicUsize::new(0));
    let received = calls.clone();
    let stub = serve(Router::new().fallback(move || {
        received.fetch_add(1, Ordering::SeqCst);
        async { "should not run" }
    }))
    .await;
    let server = media(&stub).await;
    let session = server.open(vec![source(&stub)], Quality::Standard).unwrap();
    let client = reqwest::Client::new();
    let url = &session.sources[0].url;
    assert_eq!(
        client
            .get(url.replace(&session.id, &uuid::Uuid::new_v4().to_string()))
            .send()
            .await
            .unwrap()
            .status(),
        404
    );
    assert_eq!(
        client
            .get(url)
            .header("Origin", "https://evil.example")
            .send()
            .await
            .unwrap()
            .status(),
        403
    );
    assert_eq!(
        client
            .get(url)
            .header("Host", "evil.example")
            .send()
            .await
            .unwrap()
            .status(),
        403
    );
    assert_eq!(client.post(url).send().await.unwrap().status(), 405);
    assert_eq!(
        client
            .get(url.replace("standard", "unknown"))
            .send()
            .await
            .unwrap()
            .status(),
        404
    );
    let options = client
        .request(reqwest::Method::OPTIONS, url)
        .header("Origin", "tauri://localhost")
        .send()
        .await
        .unwrap();
    assert_eq!(options.status(), 204);
    assert_eq!(
        options.headers()["access-control-allow-methods"],
        "GET, HEAD, OPTIONS"
    );
    server.close(&session.id);
    assert_eq!(client.get(url).send().await.unwrap().status(), 404);
    assert_eq!(calls.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn rejects_redirects_and_non_video_bodies_without_following_them() {
    for (status, content_type) in [(302, "video/mp4"), (200, "text/html")] {
        let stub = serve(Router::new().fallback(move || async move {
            Response::builder()
                .status(status)
                .header("Location", "http://127.0.0.1:1/forbidden")
                .header("Content-Type", content_type)
                .body(Body::from("body"))
                .unwrap()
        }))
        .await;
        let server = media(&stub).await;
        let session = server.open(vec![source(&stub)], Quality::Standard).unwrap();
        assert_eq!(
            reqwest::get(&session.sources[0].url)
                .await
                .unwrap()
                .status(),
            502
        );
    }
}

#[tokio::test]
async fn closing_a_session_cancels_an_active_stream_and_never_reuses_its_token() {
    let (started, mut received) = tokio::sync::mpsc::channel(1);
    let stub = serve(Router::new().fallback(move || {
        let started = started.clone();
        async move {
            let stream = futures_util::stream::unfold(0, move |index| {
                let started = started.clone();
                async move {
                    if index == 0 {
                        let _ = started.send(()).await;
                    }
                    tokio::time::sleep(Duration::from_millis(10)).await;
                    Some((Ok::<_, std::io::Error>(vec![0_u8; 1024]), index + 1))
                }
            });
            Response::builder()
                .header("Content-Type", "video/mp4")
                .body(Body::from_stream(stream))
                .unwrap()
        }
    }))
    .await;
    let server = media(&stub).await;
    let session = server.open(vec![source(&stub)], Quality::Standard).unwrap();
    let mut response = reqwest::get(&session.sources[0].url).await.unwrap();
    received.recv().await.unwrap();
    response.chunk().await.unwrap().unwrap();
    server.close(&session.id);
    let result = tokio::time::timeout(Duration::from_secs(1), response.bytes())
        .await
        .unwrap();
    assert!(result.is_err());
    let next = server.open(vec![source(&stub)], Quality::Standard).unwrap();
    assert_ne!(session.id, next.id);
    assert_eq!(
        reqwest::get(&session.sources[0].url)
            .await
            .unwrap()
            .status(),
        404
    );
}

#[tokio::test]
async fn dropping_the_downstream_body_stops_consuming_the_upstream_stream() {
    let sent = Arc::new(AtomicUsize::new(0));
    let captured = sent.clone();
    let stub = serve(Router::new().fallback(move || {
        let sent = captured.clone();
        async move {
            let stream = futures_util::stream::unfold(sent, |sent| async move {
                tokio::time::sleep(Duration::from_millis(5)).await;
                sent.fetch_add(1, Ordering::SeqCst);
                Some((Ok::<_, std::io::Error>(vec![0_u8; 64 * 1024]), sent))
            });
            Response::builder()
                .header("Content-Type", "video/mp4")
                .body(Body::from_stream(stream))
                .unwrap()
        }
    }))
    .await;
    let server = media(&stub).await;
    let session = server.open(vec![source(&stub)], Quality::Standard).unwrap();
    let mut response = reqwest::get(&session.sources[0].url).await.unwrap();
    response.chunk().await.unwrap().unwrap();
    drop(response);
    tokio::time::sleep(Duration::from_millis(80)).await;
    let stopped = sent.load(Ordering::SeqCst);
    tokio::time::sleep(Duration::from_millis(80)).await;
    assert_eq!(sent.load(Ordering::SeqCst), stopped);
}

#[tokio::test]
async fn separates_header_and_idle_deadlines_without_a_whole_video_timeout() {
    let delayed = serve(Router::new().fallback(|| async {
        tokio::time::sleep(Duration::from_millis(200)).await;
        Response::builder()
            .header("Content-Type", "video/mp4")
            .body(Body::empty())
            .unwrap()
    }))
    .await;
    let config = |stub: &Stub| MediaConfig {
        upstream_origin: stub.origin.clone(),
        header_timeout: Duration::from_millis(80),
        idle_timeout: Duration::from_millis(100),
        ..MediaConfig::default()
    };
    let server = MediaServer::bind(config(&delayed)).await.unwrap();
    let session = server
        .open(vec![source(&delayed)], Quality::Standard)
        .unwrap();
    assert_eq!(
        reqwest::get(&session.sources[0].url)
            .await
            .unwrap()
            .status(),
        504
    );
    for delay in [30_u64, 200] {
        let stub = serve(Router::new().fallback(move || async move {
            let stream = futures_util::stream::unfold(0, move |index| async move {
                if index == 5 {
                    return None;
                }
                tokio::time::sleep(Duration::from_millis(delay)).await;
                Some((Ok::<_, std::io::Error>(vec![index as u8; 1024]), index + 1))
            });
            Response::builder()
                .header("Content-Type", "video/mp4")
                .body(Body::from_stream(stream))
                .unwrap()
        }))
        .await;
        let server = MediaServer::bind(config(&stub)).await.unwrap();
        let session = server.open(vec![source(&stub)], Quality::Standard).unwrap();
        let response = reqwest::get(&session.sources[0].url).await.unwrap();
        assert!(!response.headers().contains_key("content-length"));
        if delay == 30 {
            assert_eq!(response.bytes().await.unwrap().len(), 5 * 1024);
        } else {
            assert!(response.bytes().await.is_err());
        }
    }
}

#[tokio::test]
async fn closing_during_response_headers_cancels_the_pending_operation() {
    let (started, mut received) = tokio::sync::mpsc::channel(1);
    let stub = serve(Router::new().fallback(move || {
        let started = started.clone();
        async move {
            started.send(()).await.unwrap();
            std::future::pending::<Response<Body>>().await
        }
    }))
    .await;
    let server = media(&stub).await;
    let session = server.open(vec![source(&stub)], Quality::Standard).unwrap();
    let url = session.sources[0].url.clone();
    let request = tokio::spawn(async move { reqwest::get(url).await.unwrap().status() });
    received.recv().await.unwrap();
    server.close(&session.id);
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(1), request)
            .await
            .unwrap()
            .unwrap(),
        410
    );
}

#[tokio::test]
async fn concurrent_ranges_and_server_shutdown_release_owned_resources() {
    let stub =
        serve(Router::new().fallback(|request: Request<Body>| async move {
            range_reply(request.headers(), false)
        }))
        .await;
    let server = media(&stub).await;
    let session = server.open(vec![source(&stub)], Quality::Standard).unwrap();
    let url = &session.sources[0].url;
    let client = reqwest::Client::new();
    let (first, second) = tokio::join!(
        client.get(url).header("Range", "bytes=0-7").send(),
        client.get(url).header("Range", "bytes=-8").send()
    );
    assert_eq!(
        first.unwrap().bytes().await.unwrap().as_ref(),
        &[0, 1, 2, 3, 4, 5, 6, 7]
    );
    assert_eq!(
        second.unwrap().bytes().await.unwrap().as_ref(),
        &[192, 193, 194, 195, 196, 197, 198, 199]
    );
    let url = url.clone();
    tokio::time::timeout(Duration::from_secs(1), server.shutdown())
        .await
        .unwrap();
    assert!(reqwest::get(url).await.is_err());
}

#[tokio::test]
async fn downstream_backpressure_does_not_prefetch_a_gibibyte_into_memory() {
    let sent = Arc::new(AtomicUsize::new(0));
    let captured = sent.clone();
    let stub = serve(Router::new().fallback(move || {
        let sent = captured.clone();
        async move {
            let stream = futures_util::stream::unfold((0, sent), |(index, sent)| async move {
                if index == 16_384 {
                    return None;
                }
                sent.fetch_add(1, Ordering::SeqCst);
                Some((
                    Ok::<_, std::io::Error>(vec![0_u8; 64 * 1024]),
                    (index + 1, sent),
                ))
            });
            Response::builder()
                .header("Content-Type", "video/mp4")
                .header("Content-Length", 1_073_741_824)
                .body(Body::from_stream(stream))
                .unwrap()
        }
    }))
    .await;
    let server = media(&stub).await;
    let session = server.open(vec![source(&stub)], Quality::Standard).unwrap();
    let mut response = reqwest::get(&session.sources[0].url).await.unwrap();
    response.chunk().await.unwrap().unwrap();
    tokio::time::sleep(Duration::from_millis(150)).await;
    assert!(
        sent.load(Ordering::SeqCst) < 2048,
        "a paused downstream prefetched at least 128 MiB"
    );
    drop(response);
    server.close(&session.id);
}

struct ActiveTransfer(Arc<AtomicUsize>);
impl Drop for ActiveTransfer {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::SeqCst);
    }
}

async fn stalled_downstream() -> (
    Stub,
    MediaServer,
    tokio::net::TcpStream,
    Arc<AtomicUsize>,
    String,
) {
    use tokio::io::AsyncWriteExt;
    let active = Arc::new(AtomicUsize::new(0));
    let sent = Arc::new(AtomicUsize::new(0));
    let active_capture = active.clone();
    let sent_capture = sent.clone();
    let stub = serve(Router::new().fallback(move || {
        let active = active_capture.clone();
        let sent = sent_capture.clone();
        async move {
            active.fetch_add(1, Ordering::SeqCst);
            let guard = ActiveTransfer(active);
            let stream =
                futures_util::stream::unfold((0, sent, guard), |(index, sent, guard)| async move {
                    if index == 16384 {
                        return None;
                    }
                    sent.fetch_add(1, Ordering::SeqCst);
                    Some((
                        Ok::<_, std::io::Error>(vec![0_u8; 64 * 1024]),
                        (index + 1, sent, guard),
                    ))
                });
            Response::builder()
                .header("Content-Type", "video/mp4")
                .header("Content-Length", 1_073_741_824)
                .body(Body::from_stream(stream))
                .unwrap()
        }
    }))
    .await;
    let server = media(&stub).await;
    let session = server.open(vec![source(&stub)], Quality::Standard).unwrap();
    let url = reqwest::Url::parse(&session.sources[0].url).unwrap();
    let address = format!("{}:{}", url.host_str().unwrap(), url.port().unwrap());
    let mut peer = tokio::net::TcpStream::connect(&address).await.unwrap();
    peer.write_all(format!("GET {} HTTP/1.1\r\nHost: {address}\r\n\r\n", url.path()).as_bytes())
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(3), async {
        let mut last = 0;
        let mut stable = 0;
        loop {
            tokio::time::sleep(Duration::from_millis(20)).await;
            let current = sent.load(Ordering::SeqCst);
            if current > 0 && current == last {
                stable += 1;
            } else {
                stable = 0;
            }
            if stable >= 3 {
                break;
            }
            last = current;
        }
    })
    .await
    .expect("raw TCP client did not backpressure the upstream");
    (stub, server, peer, active, session.id)
}

#[tokio::test]
async fn session_close_releases_upstream_even_when_the_downstream_never_reads() {
    let (_stub, server, _peer, active, id) = stalled_downstream().await;
    assert_eq!(active.load(Ordering::SeqCst), 1);
    server.close(&id);
    tokio::time::timeout(Duration::from_millis(500), async {
        while active.load(Ordering::SeqCst) != 0 {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("session close retained the backpressured upstream response");
}

#[tokio::test]
async fn server_shutdown_terminates_non_reading_downstream_connections() {
    let (_stub, server, _peer, _active, _id) = stalled_downstream().await;
    tokio::time::timeout(Duration::from_millis(500), server.shutdown())
        .await
        .expect("shutdown hung behind a non-reading TCP client");
}
