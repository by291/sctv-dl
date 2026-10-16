pub mod commands;
pub mod downloads;
pub mod error;
pub mod media;
pub mod programmes;
pub mod requests;
pub mod settings;
pub mod state;

use tauri::Manager;
use tauri_plugin_store::StoreExt;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            // Initialize identity once before any metadata command can access the service.
            let store = app
                .store_builder("desktop.json")
                .disable_auto_save()
                .build()
                .map_err(|_| error::AppError::new("storage", "无法打开桌面应用数据"));
            let identity = store
                .as_ref()
                .map_err(Clone::clone)
                .and_then(|store| settings::installation_id(store));
            let directory_store = match &identity {
                Ok(_) => store,
                Err(error) => Err(error.clone()),
            };
            let service = identity.and_then(programmes::ProgrammeService::production);
            app.manage(settings::DirectorySettings::new(directory_store));
            app.manage(tauri::async_runtime::block_on(async {
                downloads::DownloadManager::new(downloads::DownloadConfig::default())
            })?);
            app.manage(state::AppState::new(service));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::list_programmes,
            commands::list_programme_dates,
            commands::list_programme_contents,
            commands::cancel_request,
            commands::start_downloads,
            commands::list_downloads,
            commands::subscribe_downloads,
            commands::unsubscribe_downloads,
            commands::cancel_download,
            commands::get_download_directory,
            commands::choose_download_directory
        ])
        .build(tauri::generate_context!())
        .expect("failed to build the desktop application")
        .run(|app, event| {
            if matches!(event, tauri::RunEvent::Exit) {
                tauri::async_runtime::block_on(
                    app.state::<downloads::DownloadManager>().shutdown(),
                );
            }
        });
}
