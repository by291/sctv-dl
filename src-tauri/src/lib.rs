pub mod commands;
pub mod error;
pub mod programmes;
pub mod requests;
pub mod settings;
pub mod state;

use tauri::Manager;
use tauri_plugin_store::StoreExt;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::default().build())
        .setup(|app| {
            // Initialize identity once before any metadata command can access the service.
            let service = app
                .store_builder("desktop.json")
                .disable_auto_save()
                .build()
                .map_err(|_| error::AppError::new("storage", "无法打开桌面应用数据"))
                .and_then(|store| settings::installation_id(&store))
                .and_then(programmes::ProgrammeService::production);
            app.manage(state::AppState::new(service));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::list_programmes,
            commands::list_programme_dates,
            commands::list_programme_contents,
            commands::cancel_request
        ])
        .run(tauri::generate_context!())
        .expect("failed to run the desktop application");
}
