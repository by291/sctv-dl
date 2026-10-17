use sctv_dl_desktop_lib::{
    commands, lifecycle::ExitController, programme_cache::ProgrammeCacheService,
};
use serde_json::{Value, json};
use std::sync::Arc;
use tauri::{
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
async fn cache_commands_reject_remote_and_secondary_windows_and_bad_keys() {
    let root = tempfile::tempdir().unwrap();
    let app = mock_builder()
        .manage(Arc::new(ExitController::default()))
        .manage(ProgrammeCacheService::open(root.path().join("cache")).await)
        .invoke_handler(tauri::generate_handler![
            commands::read_programme_cache,
            commands::write_programme_cache,
            commands::read_archive_browse_state,
            commands::write_archive_browse_state,
            commands::clear_programme_cache
        ])
        .build(tauri::generate_context!(test = true))
        .unwrap();
    let main = tauri::WebviewWindowBuilder::new(&app, "main", Default::default())
        .build()
        .unwrap();
    let secondary = tauri::WebviewWindowBuilder::new(&app, "secondary", Default::default())
        .build()
        .unwrap();
    let origin = if cfg!(windows) {
        "http://tauri.localhost"
    } else {
        "tauri://localhost"
    };
    let initial = invoke(
        &main,
        "read_programme_cache",
        json!({"key":{"kind":"catalogue"}}),
        origin,
    )
    .unwrap();
    let body = json!({"key":{"kind":"catalogue"},"payload":{"kind":"catalogue","items":[]},"expectedEpoch":initial["epoch"],"programmeId":"1","value":{"programmeId":"1","dateId":null,"date":null,"sort":"asc","scrollY":0,"visitedAt":"2026-10-17T00:00:00.000Z"}});
    for command in [
        "read_programme_cache",
        "write_programme_cache",
        "read_archive_browse_state",
        "write_archive_browse_state",
        "clear_programme_cache",
    ] {
        assert!(invoke(&secondary, command, body.clone(), origin).is_err());
        assert!(invoke(&main, command, body.clone(), "https://external.invalid").is_err());
    }
    assert_eq!(
        invoke(
            &main,
            "read_programme_cache",
            json!({"key":{"kind":"dates","programmeId":"../private"}}),
            origin
        )
        .unwrap_err()["code"],
        "invalid-input"
    );
    assert_eq!(
        invoke(&main, "write_programme_cache", body, origin).unwrap()["persisted"],
        true
    );
}
