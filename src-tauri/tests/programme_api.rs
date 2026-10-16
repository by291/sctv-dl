use axum::{
    Json, Router,
    body::Body,
    http::{HeaderMap, Request, Response},
};
use sctv_dl_desktop_lib::programmes::{Deadlines, ProgrammeService};
use sctv_dl_desktop_lib::requests::RequestRegistry;
use serde_json::{Value, json};
use std::{
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::{net::TcpListener, task::JoinHandle};
use uuid::Uuid;

struct Stub {
    origin: String,
    task: JoinHandle<()>,
}
impl Drop for Stub {
    fn drop(&mut self) {
        self.task.abort();
    }
}
async fn serve(router: Router) -> Stub {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let task = tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    Stub { origin, task }
}
async fn json_stub(value: Value) -> Stub {
    serve(Router::new().fallback(move || {
        let value = value.clone();
        async move { Json(value) }
    }))
    .await
}
fn service(stub: &Stub) -> ProgrammeService {
    ProgrammeService::new(
        &stub.origin,
        Uuid::new_v4().to_string(),
        Deadlines::default(),
    )
    .unwrap()
}
fn envelope(data: Value) -> Value {
    json!({"rs": 200, "data": data})
}

#[tokio::test]
async fn normalizes_the_same_content_fixtures_as_node() {
    let fixtures: Vec<Value> =
        serde_json::from_str(include_str!("../../shared/fixtures/programmes.json")).unwrap();
    for fixture in fixtures {
        let stub = json_stub(envelope(fixture["raw"].clone())).await;
        let contents = service(&stub).contents("1", "2").await.unwrap();
        assert_eq!(
            serde_json::to_value(contents).unwrap(),
            fixture["expected"],
            "{}",
            fixture["name"]
        );
    }
}

#[tokio::test]
async fn preserves_large_string_ids_and_rejects_unsafe_numeric_ids() {
    for raw in [
        json!(9007199254740992_u64),
        json!(-1),
        json!(1.5),
        json!("../1"),
    ] {
        let stub = json_stub(envelope(json!({"records": [{"id": raw}]}))).await;
        assert_eq!(
            service(&stub).programmes().await.unwrap_err().code,
            "upstream"
        );
    }
    let stub = json_stub(envelope(
        json!({"records": [{"id": "9007199254740992", "cover": " /news.jpg "}]}),
    ))
    .await;
    let rows = service(&stub).programmes().await.unwrap();
    assert_eq!(rows[0].id, "9007199254740992");
    assert_eq!(rows[0].name, "未命名栏目");
    assert_eq!(
        rows[0].cover.as_deref(),
        Some("https://kscgc.sctv.com/news.jpg")
    );
}

#[tokio::test]
async fn deduplicates_dates_retaining_the_last_record_and_validates_calendar_dates() {
    let stub = json_stub(envelope(json!([
        {"id": 1, "date": "2026-10-14"}, {"id": 2, "date": "2026-10-15"}, {"id": 3, "date": "2026-10-14"}
    ]))).await;
    let dates = service(&stub).dates("1").await.unwrap();
    assert_eq!(
        serde_json::to_value(dates).unwrap(),
        json!([
            {"id": "2", "date": "2026-10-15"}, {"id": "3", "date": "2026-10-14"}
        ])
    );
    for date in ["2025-02-29", "2026-04-31", "2026-1-01"] {
        let invalid = json_stub(envelope(json!([{"id": 1, "date": date}]))).await;
        assert_eq!(
            service(&invalid).dates("1").await.unwrap_err().code,
            "upstream"
        );
    }
}

#[tokio::test]
async fn rejects_invalid_references_before_network_and_preserves_business_errors() {
    let stub = json_stub(json!({"rs": 500, "error": "Maintenance", "data": null})).await;
    let client = service(&stub);
    assert_eq!(
        client.dates("../1").await.unwrap_err().code,
        "invalid-input"
    );
    assert_eq!(
        client.contents("1", "").await.unwrap_err().code,
        "invalid-input"
    );
    let error = client.programmes().await.unwrap_err();
    assert_eq!(error.code, "upstream");
    assert_eq!(error.message, "Maintenance");
}

#[tokio::test]
async fn rejects_redirects_non_json_and_malformed_envelopes() {
    for (status, body) in [
        (302, "redirect"),
        (200, "<html>no</html>"),
        (200, "{}"),
        (200, "{\"rs\":200,\"data\":{\"records\":[{}]}}"),
    ] {
        let stub = serve(Router::new().fallback(move || async move {
            Response::builder()
                .status(status)
                .header("Location", "http://127.0.0.1:1/forbidden")
                .body(Body::from(body))
                .unwrap()
        }))
        .await;
        assert_eq!(
            service(&stub).programmes().await.unwrap_err().code,
            "upstream"
        );
    }
}

#[tokio::test]
async fn concurrent_requests_use_one_guest_identity_and_the_expected_paths() {
    let seen = Arc::new(Mutex::new(Vec::<(String, HeaderMap)>::new()));
    let captured = seen.clone();
    let stub = serve(Router::new().fallback(move |request: Request<Body>| {
        let path = request.uri().to_string();
        captured
            .lock()
            .unwrap()
            .push((path.clone(), request.headers().clone()));
        async move {
            Json(envelope(if path.contains('?') {
                json!({"records": []})
            } else {
                json!([])
            }))
        }
    }))
    .await;
    let client = service(&stub);
    let (programmes, dates, contents) = tokio::join!(
        client.programmes(),
        client.dates("1"),
        client.contents("1", "2")
    );
    programmes.unwrap();
    dates.unwrap();
    contents.unwrap();
    let seen = seen.lock().unwrap();
    let ids: Vec<_> = seen
        .iter()
        .map(|(_, headers)| headers["deviceid"].to_str().unwrap())
        .collect();
    assert!(ids.iter().all(|id| *id == ids[0]));
    assert_eq!(Uuid::parse_str(ids[0]).unwrap().get_version_num(), 4);
    for (_, headers) in seen.iter() {
        for (key, value) in [
            ("user-agent", "okhttp/4.12.0"),
            ("devicebrand", "google"),
            ("devicemodel", "Pixel 8"),
            ("systemversion", "14"),
            ("devicetype", "android"),
            ("appversion", "9.6.1.5"),
            ("userid", ""),
            ("authorization", ""),
            ("captchaid", ""),
            ("accept", "application/json"),
            ("accept-encoding", "gzip"),
        ] {
            assert_eq!(headers[key], value);
        }
        assert!(!headers.contains_key("referer"));
        assert!(!headers.contains_key("cookie"));
    }
    let mut paths: Vec<_> = seen.iter().map(|(path, _)| path.as_str()).collect();
    paths.sort();
    assert_eq!(
        paths,
        vec![
            "/app/v1/programs/1/dates/2/contents/list",
            "/app/v1/programs/1/dates/list",
            "/app/v1/programs?page=0&size=100"
        ]
    );
}

#[tokio::test]
async fn times_out_headers_and_idle_bodies_but_allows_progressing_bodies() {
    let deadlines = Deadlines {
        headers: Duration::from_millis(80),
        idle: Duration::from_millis(100),
    };
    let stub = serve(Router::new().fallback(|| async {
        tokio::time::sleep(Duration::from_millis(200)).await;
        Json(envelope(json!({"records": []})))
    }))
    .await;
    let client =
        ProgrammeService::new(&stub.origin, Uuid::new_v4().to_string(), deadlines).unwrap();
    assert_eq!(client.programmes().await.unwrap_err().code, "timeout");
    for delay in [Duration::from_millis(30), Duration::from_millis(200)] {
        let stub = serve(Router::new().fallback(move || async move {
            let chunks = vec!["{\"rs\":200,", "\"data\":{", "\"records\":", "[]}}"];
            let stream =
                futures_util::stream::unfold(chunks.into_iter(), move |mut parts| async move {
                    let part = parts.next()?;
                    tokio::time::sleep(delay).await;
                    Some((Ok::<_, std::io::Error>(part), parts))
                });
            Response::new(Body::from_stream(stream))
        }))
        .await;
        let client =
            ProgrammeService::new(&stub.origin, Uuid::new_v4().to_string(), deadlines).unwrap();
        let result = client.programmes().await;
        if delay.as_millis() == 30 {
            assert!(result.unwrap().is_empty());
        } else {
            assert_eq!(result.unwrap_err().code, "timeout");
        }
    }
}

#[tokio::test]
async fn cancels_pending_headers_and_body_reads_and_releases_registry_entries() {
    for pending_body in [false, true] {
        let (started, mut received) = tokio::sync::mpsc::channel(1);
        let stub = serve(Router::new().fallback(move || {
            let started = started.clone();
            async move {
                started.send(()).await.unwrap();
                if pending_body {
                    Response::new(Body::from_stream(futures_util::stream::pending::<
                        Result<&str, std::io::Error>,
                    >()))
                } else {
                    std::future::pending().await
                }
            }
        }))
        .await;
        let registry = Arc::new(RequestRegistry::default());
        let id = Uuid::new_v4().to_string();
        let guard = registry.register(&id).unwrap();
        let client = service(&stub);
        let task = tokio::spawn(async move { guard.run(client.programmes()).await });
        received.recv().await.unwrap();
        registry.cancel(&id).unwrap();
        let error = tokio::time::timeout(Duration::from_secs(1), task)
            .await
            .unwrap()
            .unwrap()
            .unwrap_err();
        assert_eq!(error.code, "cancelled");
        assert!(
            registry
                .register(&id)
                .unwrap()
                .run(async { Ok(()) })
                .await
                .is_ok()
        );
    }
}

#[tokio::test]
async fn preserves_safe_integer_ids_in_raw_floating_point_json_notation() {
    let stub = serve(Router::new().fallback(|| async {
        Response::new(Body::from(
            r#"{"rs":200,"data":{"records":[{"id":9007199254740991.0,"name":"Boundary"}]}}"#,
        ))
    }))
    .await;
    assert_eq!(
        service(&stub).programmes().await.unwrap()[0].id,
        "9007199254740991"
    );
}
