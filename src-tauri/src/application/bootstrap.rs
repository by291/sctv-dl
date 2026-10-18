use std::sync::Arc;

use tauri::{AppHandle, Manager, Runtime};
use tauri_plugin_store::{Store, StoreExt};
use tauri_plugin_window_state::{StateFlags, WindowExt};

use crate::{
    downloads::{DownloadConfig, DownloadManager},
    error::{AppError, ErrorCode, Result},
    history::HistoryService,
    media::{MediaConfig, PlaybackService},
    programme_cache::ProgrammeCacheService,
    programmes::ProgrammeService,
    settings::{self, DesktopSettings},
    state::{AppState, PlaybackState},
};

struct StorageIdentity<R: Runtime> {
    store: Result<Arc<Store<R>>>,
    identity: Result<String>,
}

fn initialize_storage_identity<R: Runtime>(app: &AppHandle<R>) -> StorageIdentity<R> {
    let store = app
        .store_builder("desktop.json")
        .disable_auto_save()
        .build()
        .map_err(|cause| {
            AppError::with_source(ErrorCode::Storage, "无法打开桌面应用数据", cause)
                .reported("open desktop data")
        });
    let identity = store
        .as_ref()
        .map_err(Clone::clone)
        .and_then(|store| settings::installation_id(store));

    // A failed identity disables the shared Store rather than exposing a partial setup.
    let store = match &identity {
        Ok(_) => store,
        Err(error) => Err(error.clone()),
    };

    StorageIdentity { store, identity }
}

/// Initializes identity before metadata access and preserves each service's degraded mode.
/// Download startup failure aborts setup; playback failure remains an IPC-visible result.
pub(crate) fn initialize_services<R: Runtime>(app: &AppHandle<R>) -> Result<()> {
    let StorageIdentity { store, identity } = initialize_storage_identity(app);
    let programmes = identity.and_then(ProgrammeService::production);

    app.manage(DesktopSettings::new(store));

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
