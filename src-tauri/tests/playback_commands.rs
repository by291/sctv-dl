#[path = "support/ipc.rs"]
mod ipc;

mod support;

use std::sync::Arc;

use axum::{Json, Router, http::Uri};
use sctv_dl_desktop_lib::{
    commands,
    lifecycle::ExitController,
    media::{MediaConfig, PlaybackService},
    programmes::{Deadlines, ProgrammeService},
    state::{AppState, PlaybackState},
};
use serde_json::json;
use tauri::{Manager, test::mock_builder};

use ipc::{invoke, local_origin};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn playback_commands_enforce_domain_references_acl_and_early_cancellation() {
    let router = Router::new().fallback(|uri: Uri| async move {
        let data = if uri.path().contains("contents") {
            json!([{ "id": 3, "video": "https://fscgc.scgchc.com/a.mp4" }])
        } else {
            json!([{ "id": 2, "date": "2026-10-16" }])
        };
        Json(json!({ "rs": 200, "data": data }))
    });
    let server = support::serve(router).await;

    let state = AppState::new(ProgrammeService::new(
        &server.origin,
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
    let local = local_origin();
    let request = |id: &str| {
        json!({
            "requestId": id,
            "request": {
                "programmeId": "1",
                "dateId": "2",
                "contentId": "3",
                "quality": "smooth"
            }
        })
    };

    let id = uuid::Uuid::new_v4().to_string();
    let session = invoke(&main, "open_playback", request(&id), local).unwrap();

    assert_eq!(session["selectedQuality"], "standard");

    invoke(
        &main,
        "close_playback",
        json!({ "sessionId": session["id"] }),
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
}
