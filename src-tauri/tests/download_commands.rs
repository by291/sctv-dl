use axum::{
    Json, Router,
    body::Body,
    http::{Request, Response},
};
use sctv_dl_desktop_lib::{
    commands,
    downloads::{DownloadConfig, DownloadManager},
    programmes::{Deadlines, ProgrammeService},
    settings::{DirectorySettings, save_download_directory},
    state::AppState,
};
use serde_json::{Value, json};
use tauri::{
    Manager,
    ipc::{CallbackFn, InvokeBody},
    test::{INVOKE_KEY, get_ipc_response, mock_builder},
    webview::InvokeRequest,
};
use tauri_plugin_store::StoreExt;

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
async fn downloads_through_domain_commands_and_restricts_native_access() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let upstream = origin.clone();
    let server = tokio::spawn(async move {
        axum::serve(
            listener,
            Router::new().fallback(move |request: Request<Body>| {
                let origin = upstream.clone();
                async move {
                    if request.uri().path().ends_with(".mp4") {
                        return Response::builder()
                            .header("Content-Type", "video/mp4")
                            .body(Body::from("native fixture"))
                            .unwrap();
                    }
                    let data = if request.uri().path().contains("contents") {
                        json!([{"id":3,"title":"News","video":format!("{origin}/clip.mp4")}])
                    } else {
                        json!([{"id":2,"date":"2026-10-16"}])
                    };
                    use axum::response::IntoResponse;
                    Json(json!({"rs":200,"data":data})).into_response()
                }
            }),
        )
        .await
        .unwrap();
    });
    let root = tempfile::tempdir().unwrap();
    let target = root.path().join("downloads");
    std::fs::create_dir(&target).unwrap();
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState::new(Ok(ProgrammeService::new(
            &origin,
            "guest".into(),
            Deadlines::default(),
        )
        .unwrap())))
        .manage(
            DownloadManager::new(DownloadConfig {
                upstream_origin: origin,
                ..DownloadConfig::default()
            })
            .unwrap(),
        )
        .invoke_handler(tauri::generate_handler![
            commands::start_downloads,
            commands::list_downloads,
            commands::subscribe_downloads,
            commands::unsubscribe_downloads,
            commands::cancel_download,
            commands::get_download_directory,
            commands::choose_download_directory
        ])
        .build(tauri::generate_context!(test = true))
        .unwrap();
    let store = app
        .store_builder(root.path().join("desktop.json"))
        .disable_auto_save()
        .build()
        .unwrap();
    save_download_directory(&store, &target).unwrap();
    app.manage(DirectorySettings::new(Ok(store)));
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
    let request = json!({"request":{"programmeId":"1","dateId":"2","contentIds":["3","4"],"quality":"smooth"}});
    let result = invoke(&main, "start_downloads", request.clone(), local).unwrap();
    assert_eq!(result["kind"], "native");
    assert_eq!(result["usedFallback"], true);
    assert_eq!(result["failures"][0]["contentId"], "4");
    let manager = app.state::<DownloadManager>();
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        while manager.has_active() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let tasks = invoke(&main, "list_downloads", json!({}), local).unwrap();
    assert_eq!(tasks[0]["state"], "completed");
    assert_eq!(tasks[0]["receivedBytes"], 14);
    assert_eq!(
        std::fs::read(target.join(tasks[0]["filename"].as_str().unwrap())).unwrap(),
        b"native fixture"
    );
    for command in [
        "start_downloads",
        "list_downloads",
        "subscribe_downloads",
        "unsubscribe_downloads",
        "cancel_download",
        "get_download_directory",
        "choose_download_directory",
    ] {
        assert!(invoke(&secondary, command, request.clone(), local).is_err());
        assert!(invoke(&main, command, request.clone(), "https://external.invalid").is_err());
    }
    for command in [
        "plugin:dialog|open",
        "plugin:fs|write_file",
        "plugin:store|load",
    ] {
        assert!(
            invoke(&main, command, json!({}), local)
                .unwrap_err()
                .as_str()
                .unwrap()
                .contains("not allowed")
        );
    }
    manager.shutdown().await;
    server.abort();
}
