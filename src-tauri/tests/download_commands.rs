#[path = "support/ipc.rs"]
mod ipc;

use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

use axum::{
    Json, Router,
    body::Body,
    http::{Request, Response},
    response::IntoResponse,
};
use sctv_dl_desktop_lib::{
    commands,
    downloads::{DownloadConfig, DownloadManager},
    media::{MediaConfig, PlaybackService},
    programmes::{Deadlines, ProgrammeService},
    settings::{DesktopSettings, save_download_directory},
    state::{AppState, PlaybackState},
};
use serde_json::json;
use tauri::{Manager, test::mock_builder};
use tauri_plugin_store::StoreExt;

use ipc::{invoke, local_origin};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn downloads_through_domain_commands_and_restricts_native_access() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let upstream = origin.clone();
    let refreshed = Arc::new(AtomicBool::new(false));
    let upstream_refreshed = refreshed.clone();
    let server = tokio::spawn(async move {
        axum::serve(
            listener,
            Router::new().fallback(move |request: Request<Body>| {
                let origin = upstream.clone();
                let refreshed = upstream_refreshed.load(Ordering::SeqCst);

                async move {
                    if request.uri().path().ends_with(".mp4") {
                        return Response::builder()
                            .header("Content-Type", "video/mp4")
                            .body(Body::from(if request.uri().path() == "/refreshed.mp4" {
                                "refreshed fixture"
                            } else {
                                "native fixture"
                            }))
                            .unwrap();
                    }

                    let data = if request.uri().path().contains("contents") {
                        let filename = if refreshed {
                            "refreshed.mp4"
                        } else {
                            "clip.mp4"
                        };

                        json!([{
                            "id": 3,
                            "title": "News",
                            "video": format!("{origin}/{filename}")
                        }])
                    } else if request.uri().path() == "/app/v1/programs" {
                        json!({ "records": [{ "id": 1, "name": "News" }] })
                    } else {
                        json!([{ "id": 2, "date": "2026-10-16" }])
                    };

                    Json(json!({ "rs": 200, "data": data })).into_response()
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
        .manage(std::sync::Arc::new(
            sctv_dl_desktop_lib::lifecycle::ExitController::default(),
        ))
        .manage(PlaybackState(Ok(PlaybackService::new(
            MediaConfig::default(),
        )
        .await
        .unwrap())))
        .manage(AppState::new(Ok(ProgrammeService::new(
            &origin,
            "guest".into(),
            Deadlines::default(),
        )
        .unwrap())))
        .manage(
            DownloadManager::new(DownloadConfig {
                upstream_origins: vec![origin],
                ..DownloadConfig::default()
            })
            .unwrap(),
        )
        .invoke_handler(tauri::generate_handler![
            commands::get_download_snapshot,
            commands::subscribe_download_events,
            commands::unsubscribe_download_events,
            commands::act_on_download,
            commands::open_local_playback,
            commands::close_playback,
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
    app.manage(DesktopSettings::new(Ok(store)));

    let main = tauri::WebviewWindowBuilder::new(&app, "main", Default::default())
        .build()
        .unwrap();
    let secondary = tauri::WebviewWindowBuilder::new(&app, "secondary", Default::default())
        .build()
        .unwrap();
    let local = local_origin();

    let request = json!({
        "request": {
            "programmeId": "1",
            "dateId": "2",
            "contentIds": ["3", "4"],
            "quality": "smooth"
        }
    });
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

    let snapshot = invoke(&main, "get_download_snapshot", json!({}), local).unwrap();
    assert!(snapshot["epoch"].as_str().is_some());
    assert_eq!(snapshot["tasks"], tasks);

    let session = invoke(
        &main,
        "open_local_playback",
        json!({
            "taskId": tasks[0]["id"],
            "requestId": uuid::Uuid::new_v4().to_string(),
        }),
        local,
    )
    .unwrap();
    let url = session["sources"][0]["url"].as_str().unwrap();
    assert_eq!(
        reqwest::get(url).await.unwrap().bytes().await.unwrap(),
        "native fixture"
    );

    invoke(
        &main,
        "close_playback",
        json!({ "sessionId": session["id"] }),
        local,
    )
    .unwrap();

    let stale = invoke(
        &main,
        "act_on_download",
        json!({
            "request": {
                "taskId": tasks[0]["id"],
                "attemptId": "stale",
                "action": "remove",
            }
        }),
        local,
    )
    .unwrap();
    assert_eq!(stale["kind"], "skipped");
    assert_eq!(manager.list().len(), 1);

    let deleted = invoke(
        &main,
        "act_on_download",
        json!({
            "request": {
                "taskId": tasks[0]["id"],
                "attemptId": tasks[0]["attemptId"],
                "action": "deleteFile"
            }
        }),
        local,
    )
    .unwrap();

    assert_eq!(deleted["kind"], "applied");
    assert_eq!(deleted["task"]["state"], "missing");
    assert!(!target.join(tasks[0]["filename"].as_str().unwrap()).exists());

    // A restarted task must resolve the latest source rather than retain its old URL.
    refreshed.store(true, Ordering::SeqCst);
    let restarted = invoke(
        &main,
        "act_on_download",
        json!({
            "request": {
                "taskId": tasks[0]["id"],
                "attemptId": tasks[0]["attemptId"],
                "action": "restart"
            }
        }),
        local,
    )
    .unwrap();

    assert_eq!(restarted["kind"], "applied");
    assert_ne!(restarted["task"]["attemptId"], tasks[0]["attemptId"]);
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        while manager.has_active() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();

    let current = manager.list().pop().unwrap();
    assert_eq!(
        current.state,
        sctv_dl_desktop_lib::downloads::TaskState::Completed
    );
    assert_eq!(
        std::fs::read(target.join(current.filename)).unwrap(),
        b"refreshed fixture"
    );

    for command in [
        "get_download_snapshot",
        "subscribe_download_events",
        "unsubscribe_download_events",
        "act_on_download",
        "open_local_playback",
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

    app.state::<PlaybackState>()
        .0
        .as_ref()
        .unwrap()
        .shutdown()
        .await;
    manager.shutdown().await;
    server.abort();
}
