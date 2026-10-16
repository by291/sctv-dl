pub mod commands;
pub mod downloads;
pub mod error;
pub mod lifecycle;
pub mod media;
pub mod programmes;
pub mod requests;
pub mod settings;
pub mod state;

use std::sync::Arc;
use tauri::Manager;
use tauri_plugin_store::StoreExt;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_dialog::init())
        .manage(Arc::new(lifecycle::ExitController::default()))
        .manage(lifecycle::ExitPreparation::default())
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                lifecycle::request_exit(window.app_handle());
            }
        })
        .setup(|app| {
            lifecycle::install_menu(app.handle())?;
            #[cfg(target_os = "macos")]
            lifecycle::macos::install(app.handle())?;
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
            app.manage(settings::DesktopSettings::new(directory_store));
            app.manage(tauri::async_runtime::block_on(async {
                downloads::DownloadManager::new(downloads::DownloadConfig::default())
            })?);
            app.manage(state::PlaybackState(tauri::async_runtime::block_on(
                media::PlaybackService::new(media::MediaConfig::default()),
            )));
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
            commands::choose_download_directory,
            commands::load_settings,
            commands::save_settings,
            commands::open_playback,
            commands::close_playback,
            commands::subscribe_exit,
            commands::unsubscribe_exit,
            commands::complete_exit_preparation
        ])
        .build(tauri::generate_context!())
        .expect("failed to build the desktop application")
        .run(|app, event| {
            if let tauri::RunEvent::ExitRequested { api, .. } = &event
                && !app.state::<Arc<lifecycle::ExitController>>().committed()
            {
                api.prevent_exit();
                lifecycle::request_exit(app);
            }
            if matches!(event, tauri::RunEvent::Exit) {
                tauri::async_runtime::block_on(async {
                    app.state::<downloads::DownloadManager>().shutdown().await;
                    if let Ok(playback) = &app.state::<state::PlaybackState>().0 {
                        playback.shutdown().await;
                    }
                });
            }
        });
}
