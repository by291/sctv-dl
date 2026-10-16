use crate::lifecycle::ExitController;
use std::sync::Arc;
use tauri::{AppHandle, Runtime, State, ipc::Channel};

use crate::{
    downloads::{DownloadManager, DownloadRequest, DownloadStart, DownloadTask},
    error::Result,
    programmes::{Programme, ProgrammeContent, ProgrammeDate},
    settings::DesktopSettings,
    state::AppState,
};

#[derive(serde::Serialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum DownloadResult {
    Cancelled,
    Native(DownloadStart),
}

#[tauri::command]
pub async fn start_downloads<R: Runtime>(
    app: AppHandle<R>,
    state: State<'_, AppState>,
    directories: State<'_, DesktopSettings<R>>,
    downloads: State<'_, DownloadManager>,
    request: DownloadRequest,
    lifecycle: State<'_, Arc<ExitController>>,
) -> Result<DownloadResult> {
    let _operation = lifecycle.enter().await?;
    let service = state.programmes.as_ref().map_err(Clone::clone)?;
    let quality = request.quality;
    let prepared = downloads.prepare(service, request).await?;
    if prepared.files.is_empty() {
        return Ok(DownloadResult::Native(DownloadStart {
            failures: prepared.failures,
            ..DownloadStart::default()
        }));
    }
    let Some(path) = directories.choose(&app, true).await? else {
        return Ok(DownloadResult::Cancelled);
    };
    let mut result = downloads.start(prepared.files, &path).await?;
    result.failures.extend(prepared.failures);
    result.used_fallback = downloads
        .list()
        .iter()
        .any(|task| result.task_ids.contains(&task.id) && task.quality != quality);
    Ok(DownloadResult::Native(result))
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
#[tauri::command]
pub fn get_download_directory<R: Runtime>(
    _app: AppHandle<R>,
    directories: State<'_, DesktopSettings<R>>,
) -> Result<Option<String>> {
    crate::settings::download_directory(directories.store.as_ref().map_err(Clone::clone)?)
        .map(|path| path.map(|path| path.to_string_lossy().into_owned()))
}
#[tauri::command]
pub async fn choose_download_directory<R: Runtime>(
    lifecycle: State<'_, Arc<ExitController>>,
    app: AppHandle<R>,
    directories: State<'_, DesktopSettings<R>>,
) -> Result<Option<String>> {
    let _operation = lifecycle.enter().await?;
    directories
        .choose(&app, false)
        .await
        .map(|path| path.map(|path| path.to_string_lossy().into_owned()))
}

#[tauri::command]
pub async fn list_programmes(
    state: State<'_, AppState>,
    request_id: String,
) -> Result<Vec<Programme>> {
    let request = state.requests.register(&request_id)?;
    request
        .run(async {
            state
                .programmes
                .as_ref()
                .map_err(Clone::clone)?
                .programmes()
                .await
        })
        .await
}

#[tauri::command]
pub async fn list_programme_dates(
    state: State<'_, AppState>,
    programme_id: String,
    request_id: String,
) -> Result<Vec<ProgrammeDate>> {
    let request = state.requests.register(&request_id)?;
    request
        .run(async {
            state
                .programmes
                .as_ref()
                .map_err(Clone::clone)?
                .dates(&programme_id)
                .await
        })
        .await
}

#[tauri::command]
pub async fn list_programme_contents(
    state: State<'_, AppState>,
    programme_id: String,
    date_id: String,
    request_id: String,
) -> Result<Vec<ProgrammeContent>> {
    let request = state.requests.register(&request_id)?;
    request
        .run(async {
            state
                .programmes
                .as_ref()
                .map_err(Clone::clone)?
                .contents(&programme_id, &date_id)
                .await
        })
        .await
}

#[tauri::command]
pub fn cancel_request(state: State<'_, AppState>, request_id: String) -> Result<()> {
    state.requests.cancel(&request_id)
}

#[tauri::command]
pub fn load_settings<R: Runtime>(
    _app: AppHandle<R>,
    settings: State<'_, DesktopSettings<R>>,
) -> crate::settings::SettingsSnapshot {
    let _write = settings.writes.lock().unwrap();
    crate::settings::load_preferences(
        settings
            .store
            .as_ref()
            .map(|store| store.as_ref())
            .map_err(Clone::clone),
    )
}

#[tauri::command]
pub async fn save_settings<R: Runtime>(
    _app: AppHandle<R>,
    lifecycle: State<'_, Arc<ExitController>>,
    settings: State<'_, DesktopSettings<R>>,
    value: serde_json::Value,
) -> Result<()> {
    let operation = lifecycle.enter_save().await?;
    let store = settings.store.as_ref().map_err(Clone::clone)?.clone();
    let writes = settings.writes.clone();
    tokio::task::spawn_blocking(move || {
        let _operation = operation;
        let _write = writes.lock().unwrap();
        crate::settings::save_preferences(&store, value)
    })
    .await
    .map_err(|_| crate::error::AppError::new("storage", "保存设置异常终止"))?
}

#[tauri::command]
pub async fn open_playback(
    state: State<'_, AppState>,
    playback: State<'_, crate::state::PlaybackState>,
    lifecycle: State<'_, Arc<ExitController>>,
    request: crate::media::PlaybackRequest,
    request_id: String,
) -> Result<crate::media::PlaybackSession> {
    state
        .requests
        .register(&request_id)?
        .run(async {
            let _operation = lifecycle.enter().await?;
            let programmes = state.programmes.as_ref().map_err(Clone::clone)?;
            playback
                .0
                .as_ref()
                .map_err(Clone::clone)?
                .open(programmes, request)
                .await
        })
        .await
}

#[tauri::command]
pub fn close_playback(playback: State<'_, crate::state::PlaybackState>, session_id: String) {
    if let Ok(service) = &playback.0 {
        service.close(&session_id);
    }
}

#[tauri::command]
pub fn subscribe_exit(
    preparation: State<'_, crate::lifecycle::ExitPreparation>,
    on_event: Channel<String>,
) -> String {
    preparation.subscribe(move |id| on_event.send(id).is_ok())
}

#[tauri::command]
pub fn unsubscribe_exit(
    preparation: State<'_, crate::lifecycle::ExitPreparation>,
    subscription_id: String,
) {
    preparation.unsubscribe(&subscription_id);
}

#[tauri::command]
pub fn complete_exit_preparation(
    preparation: State<'_, crate::lifecycle::ExitPreparation>,
    request_id: String,
    saved: bool,
) {
    preparation.complete(&request_id, saved);
}
