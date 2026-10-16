use std::sync::Arc;

use tauri::{AppHandle, Runtime, State};

use crate::{
    error::Result,
    lifecycle::ExitController,
    settings::{DesktopSettings, SettingsSnapshot},
};

#[tauri::command]
pub async fn get_download_directory<R: Runtime>(
    _app: AppHandle<R>,
    directories: State<'_, DesktopSettings<R>>,
) -> Result<Option<String>> {
    directories
        .directory()
        .await
        .map(|path| path.map(|path| path.to_string_lossy().into_owned()))
}

#[tauri::command]
pub async fn choose_download_directory<R: Runtime>(
    lifecycle: State<'_, Arc<ExitController>>,
    app: AppHandle<R>,
    directories: State<'_, DesktopSettings<R>>,
) -> Result<Option<String>> {
    let operation = Arc::new(lifecycle.enter().await?);
    directories
        .choose_download_directory(&app, operation)
        .await
        .map(|path| path.map(|path| path.to_string_lossy().into_owned()))
}

#[tauri::command]
pub async fn load_settings<R: Runtime>(
    _app: AppHandle<R>,
    settings: State<'_, DesktopSettings<R>>,
) -> Result<SettingsSnapshot> {
    Ok(settings.load().await)
}

#[tauri::command]
pub async fn save_settings<R: Runtime>(
    _app: AppHandle<R>,
    lifecycle: State<'_, Arc<ExitController>>,
    settings: State<'_, DesktopSettings<R>>,
    value: serde_json::Value,
) -> Result<()> {
    let operation = lifecycle.enter_save().await?;
    settings.save(value, operation).await
}
