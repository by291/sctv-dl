use std::sync::Arc;

use tauri::{AppHandle, Runtime, State};

use crate::{
    error::Result,
    lifecycle::ExitController,
    settings::{DesktopSettings, SettingsSnapshot},
};

/// Returns the saved download location if it is still a directory.
#[tauri::command]
pub async fn get_download_directory(
    directories: State<'_, DesktopSettings>,
) -> Result<Option<String>> {
    directories
        .directory()
        .await
        .map(|path| path.map(|path| path.to_string_lossy().into_owned()))
}

/// Prompts for a download directory and saves the chosen location.
#[tauri::command]
pub async fn choose_download_directory<R: Runtime>(
    lifecycle: State<'_, Arc<ExitController>>,
    app: AppHandle<R>,
    directories: State<'_, DesktopSettings>,
) -> Result<Option<String>> {
    let operation = Arc::new(lifecycle.enter().await?);

    directories
        .choose_download_directory(&app, operation)
        .await
        .map(|path| path.map(|path| path.to_string_lossy().into_owned()))
}

/// Returns public preferences, including their persistence state.
#[tauri::command]
pub async fn load_settings(settings: State<'_, DesktopSettings>) -> Result<SettingsSnapshot> {
    Ok(settings.load().await)
}

/// Saves validated public preferences without exposing private settings.
#[tauri::command]
pub async fn save_settings(
    lifecycle: State<'_, Arc<ExitController>>,
    settings: State<'_, DesktopSettings>,
    value: serde_json::Value,
) -> Result<()> {
    let operation = lifecycle.enter_save().await?;

    settings.save(value, operation).await
}
