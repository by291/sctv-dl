use axum::{Json, Router, http::Uri};
use sctv_dl_desktop_lib::{
    commands,
    error::AppError,
    programmes::{Deadlines, ProgrammeService},
    state::AppState,
};
use serde_json::{Value, json};
use tauri::{
    ipc::{CallbackFn, InvokeBody},
    test::{INVOKE_KEY, get_ipc_response, mock_builder},
    webview::InvokeRequest,
};
use uuid::Uuid;

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

fn app(state: AppState) -> tauri::App<tauri::test::MockRuntime> {
    mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .manage(state)
        .invoke_handler(tauri::generate_handler![
            commands::list_programmes,
            commands::list_programme_dates,
            commands::list_programme_contents,
            commands::cancel_request,
        ])
        .build(tauri::generate_context!(test = true))
        .unwrap()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn routes_native_commands_to_services_and_enforces_main_window_local_permissions() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        axum::serve(listener, Router::new().fallback(|uri: Uri| async move {
            Json(json!({"rs":200, "data": if uri.query().is_some() { json!({"records":[{"id":1,"name":"News"}]}) } else if uri.path().contains("contents") { json!([{"id":3,"title":"Clip"}]) } else { json!([{"id":2,"date":"2026-10-15"}]) }}))
        })).await.unwrap();
    });
    let app = app(AppState::new(Ok(ProgrammeService::new(
        &origin,
        Uuid::new_v4().to_string(),
        Deadlines::default(),
    )
    .unwrap())));
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
    for (command, args, expected) in [
        (
            "list_programmes",
            json!({}),
            json!([{"id":"1","name":"News","cover":null}]),
        ),
        (
            "list_programme_dates",
            json!({"programmeId":"1"}),
            json!([{"id":"2","date":"2026-10-15"}]),
        ),
        (
            "list_programme_contents",
            json!({"programmeId":"1","dateId":"2"}),
            json!([{"id":"3","title":"Clip","cover":null,"video":null,"smoothVideo":null,"publishedAt":null}]),
        ),
        ("cancel_request", json!({}), Value::Null),
    ] {
        let mut args = args;
        args["requestId"] = json!(Uuid::new_v4().to_string());
        assert_eq!(
            invoke(&main, command, args.clone(), local).unwrap(),
            expected
        );
        assert!(invoke(&secondary, command, args.clone(), local).is_err());
        assert!(invoke(&main, command, args, "https://external.invalid").is_err());
    }
    let denied_store = invoke(
        &main,
        "plugin:store|load",
        json!({"path":"arbitrary.json"}),
        local,
    )
    .unwrap_err();
    assert!(denied_store.as_str().unwrap().contains("not allowed"));
    let invalid = invoke(
        &main,
        "list_programme_dates",
        json!({"programmeId":"../1", "requestId":Uuid::new_v4().to_string()}),
        local,
    )
    .unwrap_err();
    assert_eq!(invalid["code"], "invalid-input");
    server.abort();
}

#[test]
fn surfaces_identity_storage_failure_without_starting_upstream_work() {
    let app = app(AppState::new(Err(AppError::new(
        "storage",
        "Storage unavailable",
    ))));
    let main = tauri::WebviewWindowBuilder::new(&app, "main", Default::default())
        .build()
        .unwrap();
    let local = if cfg!(windows) {
        "http://tauri.localhost"
    } else {
        "tauri://localhost"
    };
    let error = invoke(
        &main,
        "list_programmes",
        json!({"requestId":Uuid::new_v4().to_string()}),
        local,
    )
    .unwrap_err();
    assert_eq!(
        error,
        json!({"code":"storage", "message":"Storage unavailable"})
    );
}
