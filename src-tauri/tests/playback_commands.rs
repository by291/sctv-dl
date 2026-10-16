use axum::{Json, Router, http::Uri};
use sctv_dl_desktop_lib::{
    commands,
    lifecycle::ExitController,
    media::{MediaConfig, PlaybackService},
    programmes::{Deadlines, ProgrammeService},
    state::{AppState, PlaybackState},
};
use serde_json::{Value, json};
use std::sync::Arc;
use tauri::{
    Manager,
    ipc::{CallbackFn, InvokeBody},
    test::{INVOKE_KEY, get_ipc_response, mock_builder},
    webview::InvokeRequest,
};
fn invoke(
    window: &tauri::WebviewWindow<tauri::test::MockRuntime>,
    command: &str,
    body: Value,
    origin: &str,
) -> Result<Value, Value> {
    get_ipc_response(
        window,
        InvokeRequest {
            cmd: command.into(),
            callback: CallbackFn(0),
            error: CallbackFn(1),
            url: origin.parse().unwrap(),
            body: InvokeBody::Json(body),
            headers: Default::default(),
            invoke_key: INVOKE_KEY.into(),
        },
    )
    .map(|body| body.deserialize().unwrap())
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn playback_commands_enforce_domain_references_acl_and_early_cancellation() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        axum::serve(listener,Router::new().fallback(|uri:Uri|async move{Json(json!({"rs":200,"data":if uri.path().contains("contents"){json!([{"id":3,"video":"https://fscgc.scgchc.com/a.mp4"}])}else{json!([{"id":2,"date":"2026-10-16"}])}}))})).await.unwrap();
    });
    let state = AppState::new(ProgrammeService::new(
        &origin,
        "guest".into(),
        Deadlines::default(),
    ));
    let registry = state.requests.clone();
    let app = mock_builder()
        .manage(state)
        .manage(PlaybackState(Ok(PlaybackService::new(
            MediaConfig::default(),
        )
        .await
        .unwrap())))
        .manage(Arc::new(ExitController::default()))
        .invoke_handler(tauri::generate_handler![
            commands::open_playback,
            commands::close_playback,
            commands::cancel_request
        ])
        .build(tauri::generate_context!(test = true))
        .unwrap();
    let main = tauri::WebviewWindowBuilder::new(&app, "main", Default::default())
        .build()
        .unwrap();
    let secondary = tauri::WebviewWindowBuilder::new(&app, "secondary", Default::default())
        .build()
        .unwrap();
    let local = if cfg!(windows) {
        "http://tauri.localhost"
    } else {
        "tauri://localhost"
    };
    let request = |id: &str| json!({"requestId":id,"request":{"programmeId":"1","dateId":"2","contentId":"3","quality":"smooth"}});
    let id = uuid::Uuid::new_v4().to_string();
    let session = invoke(&main, "open_playback", request(&id), local).unwrap();
    assert_eq!(session["selectedQuality"], "standard");
    invoke(
        &main,
        "close_playback",
        json!({"sessionId":session["id"]}),
        local,
    )
    .unwrap();
    assert_eq!(
        reqwest::get(session["sources"][0]["url"].as_str().unwrap())
            .await
            .unwrap()
            .status(),
        404
    );
    for command in ["open_playback", "close_playback"] {
        assert!(invoke(&secondary, command, request(&id), local).is_err());
        assert!(invoke(&main, command, request(&id), "https://external.invalid").is_err());
    }
    let early = uuid::Uuid::new_v4().to_string();
    registry.cancel(&early).unwrap();
    assert_eq!(
        invoke(&main, "open_playback", request(&early), local).unwrap_err()["code"],
        "cancelled"
    );
    app.state::<PlaybackState>()
        .0
        .as_ref()
        .unwrap()
        .shutdown()
        .await;
    server.abort();
}
