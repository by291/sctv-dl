#[path = "support/ipc.rs"]
mod ipc;

use std::sync::Arc;

use sctv_dl_desktop_lib::{lifecycle::ExitController, settings::DesktopSettings};
use serde_json::json;
use tauri::{Manager, test::mock_builder};

use ipc::{CommandInvocation, assert_permission_denied, invoke, local_origin};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn preferences_use_domain_commands_and_reject_untrusted_windows_and_exit_time_writes() {
    let root = tempfile::tempdir().unwrap();
    let controller = Arc::new(ExitController::default());
    let app = mock_builder()
        .manage(controller.clone())
        .invoke_handler(sctv_dl_desktop_lib::create_command_handler())
        .build(tauri::generate_context!(test = true))
        .unwrap();

    let (settings, _) = DesktopSettings::open(&root.path().join("desktop.json")).unwrap();
    app.manage(settings);

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

    invoke(CommandInvocation {
        window: &main,
        command: "save_settings",
        body: body.clone(),
        origin,
    })
    .unwrap();
    let snapshot = invoke(CommandInvocation {
        window: &main,
        command: "load_settings",
        body: json!({}),
        origin,
    })
    .unwrap();
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

    // Queued frontend saves still reach Rust during exit preparation.
    invoke(CommandInvocation {
        window: &main,
        command: "save_settings",
        body: body.clone(),
        origin,
    })
    .unwrap();

    let downloads =
        sctv_dl_desktop_lib::downloads::DownloadManager::new(Default::default()).unwrap();
    assert!(closing.complete(&downloads, || async { false }).await);
    assert_eq!(
        invoke(CommandInvocation {
            window: &main,
            command: "save_settings",
            body,
            origin,
        })
        .unwrap_err()["code"],
        "cancelled"
    );
}
