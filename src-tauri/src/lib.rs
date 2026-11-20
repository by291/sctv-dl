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

/// Creates the command dispatcher shared by native startup and IPC integration tests.
pub fn create_command_handler<R: tauri::Runtime>()
-> impl Fn(tauri::ipc::Invoke<R>) -> bool + Send + Sync + 'static {
    tauri::generate_handler![
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
    ]
}

/// Starts the desktop application and its owned native services.
pub fn run() {
    let window_state_flags = StateFlags::SIZE | StateFlags::POSITION | StateFlags::MAXIMIZED;
    let window_state = tauri_plugin_window_state::Builder::default()
        .with_filter(|label| label == "main")
        // Setup restores the initially hidden window before showing it.
        .skip_initial_state("main");
    // Hidden and fullscreen playback states must not replace the normal window bounds.
    let window_state = window_state.with_state_flags(window_state_flags).build();

    let builder = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init());
    // Persistence follows actual app exit, so cancelling exit keeps tracking active.
    let builder = builder
        .plugin(window_state)
        .manage(Arc::new(lifecycle::ExitController::default()))
        .manage(lifecycle::ExitPreparation::default());

    let builder = builder
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
        .invoke_handler(create_command_handler());
    let application = builder
        .build(tauri::generate_context!())
        .expect("failed to build the desktop application");

    application.run(|app, event| {
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
