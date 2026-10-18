use std::sync::Arc;

use tauri::State;

use crate::{
    error::Result,
    lifecycle::ExitController,
    programme_cache::{
        BrowseRead, BrowseState, CacheKey, CachePayload, CacheRead, CacheWriteResult, ClearResult,
        ProgrammeCacheService, WriteResult,
    },
};

#[tauri::command]
pub async fn read_programme_cache(
    cache: State<'_, ProgrammeCacheService>,
    lifecycle: State<'_, Arc<ExitController>>,
    key: CacheKey,
) -> Result<CacheRead> {
    cache.read(key, lifecycle.enter_save().await?).await
}

#[tauri::command]
pub async fn write_programme_cache(
    cache: State<'_, ProgrammeCacheService>,
    lifecycle: State<'_, Arc<ExitController>>,
    payload: CachePayload,
    expected_epoch: String,
) -> Result<CacheWriteResult> {
    cache
        .write(payload, expected_epoch, lifecycle.enter_save().await?)
        .await
}

#[tauri::command]
pub async fn read_archive_browse_state(
    cache: State<'_, ProgrammeCacheService>,
    lifecycle: State<'_, Arc<ExitController>>,
    programme_id: String,
) -> Result<BrowseRead> {
    cache
        .read_browse(programme_id, lifecycle.enter_save().await?)
        .await
}

#[tauri::command]
pub async fn write_archive_browse_state(
    cache: State<'_, ProgrammeCacheService>,
    lifecycle: State<'_, Arc<ExitController>>,
    value: BrowseState,
    expected_epoch: String,
) -> Result<WriteResult> {
    cache
        .write_browse(value, expected_epoch, lifecycle.enter_save().await?)
        .await
}

#[tauri::command]
pub async fn clear_programme_cache(
    cache: State<'_, ProgrammeCacheService>,
    lifecycle: State<'_, Arc<ExitController>>,
) -> Result<ClearResult> {
    cache.clear(lifecycle.enter_save().await?).await
}
