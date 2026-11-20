#[path = "support/ipc.rs"]
mod ipc;

use std::sync::Arc;

use sctv_dl_desktop_lib::{history::HistoryService, lifecycle::ExitController};
use serde_json::json;
use tauri::test::mock_builder;

use ipc::{CommandInvocation, assert_permission_denied, invoke, local_origin};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn history_commands_are_local_main_only_and_saves_drain_before_exit() {
    let root = tempfile::tempdir().unwrap();
    let controller = Arc::new(ExitController::default());
    let app = mock_builder()
        .manage(controller.clone())
        .manage(HistoryService::open(root.path().join("history-v1.json")).await)
        .invoke_handler(sctv_dl_desktop_lib::create_command_handler())
        .build(tauri::generate_context!(test = true))
        .unwrap();
    let main = tauri::WebviewWindowBuilder::new(&app, "main", Default::default())
        .build()
        .unwrap();
    let secondary = tauri::WebviewWindowBuilder::new(&app, "secondary", Default::default())
        .build()
        .unwrap();
    let origin = local_origin();

    let metadata = json!({
        "content": {
            "programmeId": "1",
            "dateId": "2",
            "contentId": "3"
        },
        "programmeName": "News",
        "broadcastDate": "2026-10-17",
        "title": "Evening",
        "cover": null
    });
    let session = invoke(CommandInvocation {
        window: &main,
        command: "begin_history",
        body: json!({"metadata": metadata}),
        origin,
    })
    .unwrap();
    let record = json!({
        "sessionId": session["id"],
        "sample": {
            "positionMs": 300000,
            "durationMs": 1000000,
            "ended": false,
            "sequence": 1
        }
    });

    let requests = [
        ("list_history", json!({})),
        ("begin_history", json!({"metadata": metadata})),
        ("record_history", record.clone()),
        ("end_history", json!({"sessionId": session["id"]})),
        ("remove_history", json!({"content": metadata["content"]})),
        ("clear_history", json!({})),
        ("subscribe_history", json!({"onEvent": "__CHANNEL__:7"})),
        ("unsubscribe_history", json!({"subscriptionId": "unknown"})),
    ];
    for (command, body) in &requests {
        assert_permission_denied(invoke(CommandInvocation {
            window: &secondary,
            command,
            body: body.clone(),
            origin,
        }));
        assert_permission_denied(invoke(CommandInvocation {
            window: &main,
            command,
            body: body.clone(),
            origin: "https://external.invalid",
        }));
    }

    let closing = controller.begin().unwrap();
    assert_eq!(
        invoke(CommandInvocation {
            window: &main,
            command: "record_history",
            body: record,
            origin,
        })
        .unwrap(),
        json!({"accepted": true, "persisted": true})
    );

    let snapshot = invoke(CommandInvocation {
        window: &main,
        command: "list_history",
        body: json!({}),
        origin,
    })
    .unwrap();
    assert_eq!(snapshot["entries"][0]["positionMs"], 300000);

    let subscription = invoke(CommandInvocation {
        window: &main,
        command: "subscribe_history",
        body: json!({"onEvent": "__CHANNEL__:7"}),
        origin,
    })
    .unwrap();
    invoke(CommandInvocation {
        window: &main,
        command: "unsubscribe_history",
        body: json!({"subscriptionId": subscription}),
        origin,
    })
    .unwrap();

    let downloads =
        sctv_dl_desktop_lib::downloads::DownloadManager::new(Default::default()).unwrap();
    assert!(closing.complete(&downloads, || async { false }).await);
    for (command, body) in &requests[1..6] {
        assert_eq!(
            invoke(CommandInvocation {
                window: &main,
                command,
                body: body.clone(),
                origin,
            })
            .unwrap_err()["code"],
            "cancelled",
            "{command}"
        );
    }
}
