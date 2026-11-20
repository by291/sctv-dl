#[path = "support/ipc.rs"]
mod ipc;

mod support;

use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

use axum::{Json, Router, http::Uri};
use sctv_dl_desktop_lib::{
    lifecycle::ExitController,
    media::{MediaConfig, PlaybackService},
    programmes::{Deadlines, ProgrammeService},
    state::{AppState, PlaybackState},
};
use serde_json::json;
use tauri::{Manager, test::mock_builder};

use ipc::{CommandInvocation, assert_permission_denied, invoke, local_origin};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn playback_commands_enforce_domain_references_acl_and_early_cancellation() {
    let upstream_calls = Arc::new(AtomicUsize::new(0));
    let captured_calls = upstream_calls.clone();
    let router = Router::new().fallback(move |uri: Uri| {
        captured_calls.fetch_add(1, Ordering::SeqCst);

        async move {
            let data = if uri.path().contains("contents") {
                json!([{ "id": 3, "video": "https://fscgc.scgchc.com/a.mp4" }])
            } else {
                json!([{ "id": 2, "date": "2026-10-16" }])
            };
            Json(json!({ "rs": 200, "data": data }))
        }
    });
    let server = support::serve(router).await;

    let state = AppState::new(ProgrammeService::new(
        &server.origin,
        "guest".into(),
        Deadlines::default(),
    ));
    let app = mock_builder()
        .manage(state)
        .manage(PlaybackState(Ok(PlaybackService::new(
            MediaConfig::default(),
        )
        .await
        .unwrap())))
        .manage(Arc::new(ExitController::default()))
        .invoke_handler(sctv_dl_desktop_lib::create_command_handler())
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
    let session = invoke(CommandInvocation {
        window: &main,
        command: "open_playback",
        body: request(&id),
        origin: local,
    })
    .unwrap();

    assert_eq!(session["selectedQuality"], "standard");

    invoke(CommandInvocation {
        window: &main,
        command: "close_playback",
        body: json!({ "sessionId": session["id"] }),
        origin: local,
    })
    .unwrap();
    assert_eq!(
        reqwest::get(session["sources"][0]["url"].as_str().unwrap())
            .await
            .unwrap()
            .status(),
        404
    );

    for (command, body) in [
        ("open_playback", request(&uuid::Uuid::new_v4().to_string())),
        ("close_playback", json!({ "sessionId": session["id"] })),
    ] {
        assert_permission_denied(invoke(CommandInvocation {
            window: &secondary,
            command,
            body: body.clone(),
            origin: local,
        }));
        assert_permission_denied(invoke(CommandInvocation {
            window: &main,
            command,
            body,
            origin: "https://external.invalid",
        }));
    }

    let early = uuid::Uuid::new_v4().to_string();
    let calls_before_cancellation = upstream_calls.load(Ordering::SeqCst);
    invoke(CommandInvocation {
        window: &main,
        command: "cancel_request",
        body: json!({ "requestId": early }),
        origin: local,
    })
    .unwrap();
    assert_eq!(
        invoke(CommandInvocation {
            window: &main,
            command: "open_playback",
            body: request(&early),
            origin: local,
        })
        .unwrap_err()["code"],
        "cancelled"
    );
    assert_eq!(
        upstream_calls.load(Ordering::SeqCst),
        calls_before_cancellation
    );

    app.state::<PlaybackState>()
        .0
        .as_ref()
        .unwrap()
        .shutdown()
        .await;
}
