use std::sync::Arc;

use tauri::{AppHandle, Runtime, State, ipc::Channel};

pub use crate::application::downloads::DownloadResult;
use crate::{
    application::downloads::DownloadService,
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
pub fn cancel_download(downloads: State<'_, DownloadManager>, task_id: String) {
    downloads.cancel(&task_id);
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
