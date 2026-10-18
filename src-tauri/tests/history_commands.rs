#[path = "support/ipc.rs"]
mod ipc;

use std::sync::Arc;

use sctv_dl_desktop_lib::{commands, history::HistoryService, lifecycle::ExitController};
use serde_json::json;
use tauri::test::mock_builder;

use ipc::{invoke, local_origin};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn history_commands_are_local_main_only_and_saves_drain_before_exit() {
    let root = tempfile::tempdir().unwrap();
    let controller = Arc::new(ExitController::default());
    let app = mock_builder()
        .manage(controller.clone())
        .manage(HistoryService::open(root.path().join("history-v1.json")).await)
        .invoke_handler(tauri::generate_handler![
            commands::list_history,
            commands::begin_history,
            commands::record_history,
            commands::end_history,
            commands::remove_history,
            commands::clear_history,
            commands::subscribe_history,
            commands::unsubscribe_history
        ])
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
    let session = invoke(
        &main,
        "begin_history",
        json!({"metadata": metadata}),
        origin,
    )
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
        assert!(
            invoke(&secondary, command, body.clone(), origin).is_err(),
            "{command}"
        );
        assert!(
            invoke(&main, command, body.clone(), "https://external.invalid").is_err(),
            "{command}"
        );
    }

    let closing = controller.begin().unwrap();
    assert_eq!(
        invoke(&main, "record_history", record, origin).unwrap(),
        json!({"accepted": true, "persisted": true})
    );

    let snapshot = invoke(&main, "list_history", json!({}), origin).unwrap();
    assert_eq!(snapshot["entries"][0]["positionMs"], 300000);

    let subscription = invoke(
        &main,
        "subscribe_history",
        json!({"onEvent": "__CHANNEL__:7"}),
        origin,
    )
    .unwrap();
    invoke(
        &main,
        "unsubscribe_history",
        json!({"subscriptionId": subscription}),
        origin,
    )
    .unwrap();

    let downloads =
        sctv_dl_desktop_lib::downloads::DownloadManager::new(Default::default()).unwrap();
    assert!(closing.complete(&downloads, || async { false }).await);
    for (command, body) in &requests[1..6] {
        assert_eq!(
            invoke(&main, command, body.clone(), origin).unwrap_err()["code"],
            "cancelled",
            "{command}"
        );
    }
}
