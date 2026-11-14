use tauri::{AppHandle, Manager, Runtime};
use tauri_plugin_window_state::{StateFlags, WindowExt};

use crate::{
    downloads::{DownloadConfig, DownloadManager},
    error::{AppError, ErrorCode, Result},
    history::HistoryService,
    media::{MediaConfig, PlaybackService},
    programme_cache::ProgrammeCacheService,
    programmes::ProgrammeService,
    settings::DesktopSettings,
    state::{AppState, PlaybackState},
};

/// Initializes identity before metadata access and preserves each service's degraded mode.
/// Download startup failure aborts setup; playback failure remains an IPC-visible result.
pub(crate) fn initialize_services<R: Runtime>(app: &AppHandle<R>) -> Result<()> {
    let settings = app
        .path()
        .app_data_dir()
        .map_err(|cause| {
            AppError::with_source(ErrorCode::Storage, "无法打开桌面应用数据", cause)
                .reported("resolve desktop data directory")
        })
        .and_then(|directory| DesktopSettings::open(&directory.join("desktop.json")));
    let (settings, programmes) = match settings {
        Ok((settings, identity)) => (settings, ProgrammeService::production(identity)),
        Err(error) => (DesktopSettings::unavailable(error.clone()), Err(error)),
    };

    app.manage(settings);
    app.manage(initialize_history(app));
    app.manage(initialize_programme_cache(app));
    app.manage(initialize_downloads(app)?);

    app.manage(PlaybackState(tauri::async_runtime::block_on(
        PlaybackService::new(MediaConfig::default()),
    )));
    app.manage(AppState::new(programmes));

    Ok(())
}

fn initialize_history<R: Runtime>(app: &AppHandle<R>) -> HistoryService {
    match app.path().app_data_dir() {
        Ok(directory) => {
            tauri::async_runtime::block_on(HistoryService::open(directory.join("history-v1.json")))
        }
        Err(cause) => HistoryService::unavailable(AppError::with_source(
            ErrorCode::Storage,
            "无法访问观看记录目录，本次记录仅在当前会话保存",
            cause,
        )),
    }
}

fn initialize_programme_cache<R: Runtime>(app: &AppHandle<R>) -> ProgrammeCacheService {
    match app.path().app_cache_dir() {
        Ok(directory) => tauri::async_runtime::block_on(ProgrammeCacheService::open(
            directory.join("programme-cache"),
        )),
        Err(cause) => ProgrammeCacheService::unavailable(AppError::with_source(
            ErrorCode::Storage,
            "无法访问节目缓存目录，本次缓存仅在当前会话保存",
            cause,
        )),
    }
}

fn initialize_downloads<R: Runtime>(app: &AppHandle<R>) -> Result<DownloadManager> {
    match app.path().app_data_dir() {
        Ok(directory) => tauri::async_runtime::block_on(DownloadManager::open(
            DownloadConfig::default(),
            directory.join("downloads-v1.json"),
        )),
        Err(cause) => DownloadManager::unavailable(
            DownloadConfig::default(),
            AppError::with_source(ErrorCode::Storage, "无法访问下载记录目录", cause),
        ),
    }
}

pub(crate) fn restore_main_window<R: Runtime>(
    app: &AppHandle<R>,
    flags: StateFlags,
) -> tauri::Result<()> {
    if let Some(window) = app.get_webview_window("main") {
        // Show even when restoration fails; visibility is never persisted.
        if let Err(error) = window.restore_state(flags) {
            eprintln!("[desktop] restore window state: {error}");
        }

        window.show()?;
    }

    Ok(())
}
