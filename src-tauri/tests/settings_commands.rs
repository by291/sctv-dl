#[path = "support/ipc.rs"]
mod ipc;

use std::sync::Arc;

use sctv_dl_desktop_lib::{commands, lifecycle::ExitController, settings::DesktopSettings};
use serde_json::json;
use tauri::{Manager, test::mock_builder};
use tauri_plugin_store::StoreExt;

use ipc::{invoke, local_origin};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn preferences_use_domain_commands_and_reject_untrusted_windows_and_exit_time_writes() {
    let root = tempfile::tempdir().unwrap();
    let controller = Arc::new(ExitController::default());
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .manage(controller.clone())
        .invoke_handler(tauri::generate_handler![
            commands::load_settings,
            commands::save_settings
        ])
        .build(tauri::generate_context!(test = true))
        .unwrap();

    let store = app
        .store_builder(root.path().join("desktop.json"))
        .disable_auto_save()
        .build()
        .unwrap();
    store.set("installationId", json!("private"));
    app.manage(DesktopSettings::new(Ok(store)));

    let main = tauri::WebviewWindowBuilder::new(&app, "main", Default::default())
        .build()
        .unwrap();
    let secondary = tauri::WebviewWindowBuilder::new(&app, "secondary", Default::default())
        .build()
        .unwrap();
    let origin = local_origin();

    let body = json!({
        "value": {
            "theme": "dark",
            "quality": "smooth",
            "favourites": ["1"]
        }
    });

    invoke(&main, "save_settings", body.clone(), origin).unwrap();
    let snapshot = invoke(&main, "load_settings", json!({}), origin).unwrap();
    assert_eq!(
        snapshot,
        json!({
            "value": {
                "theme": "dark",
                "quality": "smooth",
                "favourites": ["1"]
            },
            "persisted": true
        })
    );

    for command in ["load_settings", "save_settings"] {
        assert!(invoke(&secondary, command, body.clone(), origin).is_err());
        assert!(invoke(&main, command, body.clone(), "https://external.invalid").is_err());
    }

    let closing = controller.begin().unwrap();

    // Queued frontend saves still reach Rust during exit preparation.
    invoke(&main, "save_settings", body.clone(), origin).unwrap();

    let downloads =
        sctv_dl_desktop_lib::downloads::DownloadManager::new(Default::default()).unwrap();
    assert!(closing.complete(&downloads, || async { false }).await);
    assert_eq!(
        invoke(&main, "save_settings", body, origin).unwrap_err()["code"],
        "cancelled"
    );
}
