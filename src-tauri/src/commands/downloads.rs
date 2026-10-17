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
    use crate::downloads::{DownloadAction, DownloadActionResult};
    let operation = Arc::new(lifecycle.enter().await?);
    let task = downloads.task(&request.task_id)?;
    if task.attempt_id != request.attempt_id {
        return Ok(DownloadActionResult::Skipped {
            message: "任务已更新，请刷新后重试".into(),
        });
    }
    if matches!(
        request.action,
        DownloadAction::DeleteFile | DownloadAction::OpenFile | DownloadAction::RevealFile
    ) {
        return crate::application::download_files::act_on_file(
            app,
            &downloads,
            playback.0.as_ref().ok().cloned(),
            request,
            operation,
        )
        .await
        .map_err(|error| error.reported("download file action"));
    }
    let prepared = if matches!(
        request.action,
        DownloadAction::Resume | DownloadAction::Restart
    ) {
        let service = state.programmes.as_ref().map_err(Clone::clone)?;
        let mut batch = downloads
            .prepare(
                service,
                DownloadRequest {
                    programme_id: task.content.programme_id,
                    date_id: task.content.date_id,
                    content_ids: vec![task.content.content_id],
                    quality: task.quality,
                },
            )
            .await?;
        Some(batch.files.pop().ok_or_else(|| {
            crate::error::AppError::new(crate::error::ErrorCode::NotFound, "节目视频来源已不可用")
        })?)
    } else {
        None
    };
    downloads
        .act(request, prepared, operation)
        .await
        .map_err(|error| error.reported("download action"))
}
