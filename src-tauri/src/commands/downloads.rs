use std::sync::Arc;

use tauri::{AppHandle, Runtime, State, ipc::Channel};

pub use crate::application::downloads::DownloadResult;
use crate::{
    application::downloads::{DownloadActionService, DownloadService},
    downloads::{DownloadManager, DownloadRequest, DownloadTask},
    error::Result,
    lifecycle::ExitController,
    settings::DesktopSettings,
    state::AppState,
};

#[tauri::command]
pub async fn start_downloads<R: Runtime>(
    app: AppHandle<R>,
    state: State<'_, AppState>,
    directories: State<'_, DesktopSettings<R>>,
    downloads: State<'_, DownloadManager>,
    request: DownloadRequest,
    lifecycle: State<'_, Arc<ExitController>>,
) -> Result<DownloadResult> {
    DownloadService::new(&state, &directories, &downloads, &lifecycle)
        .start(&app, request)
        .await
        .map_err(|error| error.reported("start downloads"))
}

#[tauri::command]
pub fn list_downloads(downloads: State<'_, DownloadManager>) -> Vec<DownloadTask> {
    downloads.list()
}

#[tauri::command]
pub async fn cancel_download(
    downloads: State<'_, DownloadManager>,
    lifecycle: State<'_, Arc<ExitController>>,
    task_id: String,
) -> Result<()> {
    let Ok(task) = downloads.task(&task_id) else {
        return Ok(());
    };

    let operation = Arc::new(lifecycle.enter().await?);

    downloads
        .act(
            crate::downloads::DownloadActionRequest {
                task_id,
                attempt_id: task.attempt_id,
                action: crate::downloads::DownloadAction::Cancel,
            },
            None,
            operation,
        )
        .await?;

    Ok(())
}

#[tauri::command]
pub fn subscribe_downloads(
    downloads: State<'_, DownloadManager>,
    on_event: Channel<DownloadTask>,
) -> String {
    downloads.subscribe(move |task| on_event.send(task).is_ok())
}

#[tauri::command]
pub fn unsubscribe_downloads(downloads: State<'_, DownloadManager>, subscription_id: String) {
    downloads.unsubscribe(&subscription_id);
}

#[tauri::command]
pub fn get_download_snapshot(
    downloads: State<'_, DownloadManager>,
) -> Result<crate::downloads::DownloadSnapshot> {
    downloads.snapshot()
}

#[tauri::command]
pub fn subscribe_download_events(
    downloads: State<'_, DownloadManager>,
    on_event: Channel<crate::downloads::DownloadEvent>,
) -> Result<String> {
    downloads.subscribe_events(move |event| on_event.send(event).is_ok())
}

#[tauri::command]
pub fn unsubscribe_download_events(downloads: State<'_, DownloadManager>, subscription_id: String) {
    downloads.unsubscribe_events(&subscription_id);
}

#[tauri::command]
pub async fn act_on_download<R: Runtime>(
    app: AppHandle<R>,
    state: State<'_, AppState>,
    downloads: State<'_, DownloadManager>,
    playback: State<'_, crate::state::PlaybackState>,
    lifecycle: State<'_, Arc<ExitController>>,
    request: crate::downloads::DownloadActionRequest,
) -> Result<crate::downloads::DownloadActionResult> {
    DownloadActionService::new(&state, &downloads, &playback, &lifecycle)
        .act(app, request)
        .await
}
