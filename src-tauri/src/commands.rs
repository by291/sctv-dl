use tauri::{AppHandle, Runtime, State, ipc::Channel};

use crate::{
    downloads::{DownloadManager, DownloadRequest, DownloadStart, DownloadTask},
    error::Result,
    programmes::{Programme, ProgrammeContent, ProgrammeDate},
    settings::DirectorySettings,
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
    directories: State<'_, DirectorySettings<R>>,
    downloads: State<'_, DownloadManager>,
    request: DownloadRequest,
) -> Result<DownloadResult> {
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
    directories: State<'_, DirectorySettings<R>>,
) -> Result<Option<String>> {
    crate::settings::download_directory(directories.store.as_ref().map_err(Clone::clone)?)
        .map(|path| path.map(|path| path.to_string_lossy().into_owned()))
}
#[tauri::command]
pub async fn choose_download_directory<R: Runtime>(
    app: AppHandle<R>,
    directories: State<'_, DirectorySettings<R>>,
) -> Result<Option<String>> {
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
