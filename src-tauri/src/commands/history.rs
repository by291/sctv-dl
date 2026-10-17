use std::sync::Arc;
use tauri::{State, ipc::Channel};

use crate::{
    error::Result,
    history::{
        ContentRef, HistoryMetadata, HistorySample, HistoryService, HistorySession,
        HistorySnapshot, RecordResult,
    },
    lifecycle::ExitController,
};

#[tauri::command]
pub fn list_history(history: State<'_, HistoryService>) -> HistorySnapshot {
    history.list()
}

#[tauri::command]
pub async fn begin_history(
    history: State<'_, HistoryService>,
    lifecycle: State<'_, Arc<ExitController>>,
    metadata: HistoryMetadata,
) -> Result<HistorySession> {
    history.begin(metadata, lifecycle.enter_save().await?).await
}

#[tauri::command]
pub async fn record_history(
    history: State<'_, HistoryService>,
    lifecycle: State<'_, Arc<ExitController>>,
    session_id: String,
    sample: HistorySample,
) -> Result<RecordResult> {
    history
        .record(session_id, sample, lifecycle.enter_save().await?)
        .await
}

#[tauri::command]
pub async fn end_history(
    history: State<'_, HistoryService>,
    lifecycle: State<'_, Arc<ExitController>>,
    session_id: String,
) -> Result<()> {
    history.end(session_id, lifecycle.enter_save().await?).await
}

#[tauri::command]
pub async fn remove_history(
    history: State<'_, HistoryService>,
    lifecycle: State<'_, Arc<ExitController>>,
    content: ContentRef,
) -> Result<()> {
    history.remove(content, lifecycle.enter_save().await?).await
}

#[tauri::command]
pub async fn clear_history(
    history: State<'_, HistoryService>,
    lifecycle: State<'_, Arc<ExitController>>,
) -> Result<()> {
    history.clear(lifecycle.enter_save().await?).await
}

#[tauri::command]
pub fn subscribe_history(
    history: State<'_, HistoryService>,
    on_event: Channel<HistorySnapshot>,
) -> String {
    history.subscribe(move |snapshot| on_event.send(snapshot).is_ok())
}

#[tauri::command]
pub fn unsubscribe_history(history: State<'_, HistoryService>, subscription_id: String) {
    history.unsubscribe(&subscription_id);
}
