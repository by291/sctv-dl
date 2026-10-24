mod application;
pub mod commands;
pub mod downloads;
pub mod error;
pub mod history;
pub mod lifecycle;
pub mod media;
pub mod programme_cache;
pub mod programmes;
pub mod requests;
pub mod settings;
pub mod state;
pub mod storage;
mod upstream;

use std::sync::Arc;

use tauri::Manager;
use tauri_plugin_window_state::StateFlags;

pub fn run() {
    let window_state_flags = StateFlags::SIZE | StateFlags::POSITION | StateFlags::MAXIMIZED;

    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(
            tauri_plugin_window_state::Builder::default()
                .with_filter(|label| label == "main")
                // Setup restores the initially hidden window before showing it.
                .skip_initial_state("main")
                // Keep normal bounds and maximization, without restoring hidden or
                // fullscreen playback states. Persistence follows actual app exit,
                // so cancelling our exit confirmation leaves tracking active.
                .with_state_flags(window_state_flags)
                .build(),
        )
        .manage(Arc::new(lifecycle::ExitController::default()))
        .manage(lifecycle::ExitPreparation::default())
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                lifecycle::request_exit(window.app_handle());
            }
        })
        .setup(move |app| {
            lifecycle::install_menu(app.handle())?;
            #[cfg(target_os = "macos")]
            lifecycle::macos::install(app.handle())?;

            application::bootstrap::initialize_services(app.handle())?;
            application::bootstrap::restore_main_window(app.handle(), window_state_flags)?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::read_programme_cache,
            commands::write_programme_cache,
            commands::read_archive_browse_state,
            commands::write_archive_browse_state,
            commands::clear_programme_cache,
            commands::list_history,
            commands::begin_history,
            commands::record_history,
            commands::end_history,
            commands::remove_history,
            commands::clear_history,
            commands::subscribe_history,
            commands::unsubscribe_history,
            commands::list_programmes,
            commands::list_programme_dates,
            commands::list_programme_contents,
            commands::cancel_request,
            commands::get_download_snapshot,
            commands::subscribe_download_events,
            commands::unsubscribe_download_events,
            commands::act_on_download,
            commands::open_local_playback,
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
