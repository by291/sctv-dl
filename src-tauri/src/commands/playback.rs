use std::sync::Arc;

use tauri::State;

use crate::{
    error::Result,
    lifecycle::ExitController,
    media::{PlaybackRequest, PlaybackSession},
    state::{AppState, PlaybackState},
};

/// Resolves programme IDs into a cancellable online playback session.
#[tauri::command]
pub async fn open_playback(
    state: State<'_, AppState>,
    playback: State<'_, PlaybackState>,
    lifecycle: State<'_, Arc<ExitController>>,
    request: PlaybackRequest,
    request_id: String,
) -> Result<PlaybackSession> {
    let registered = state.requests.register(&request_id)?;
    let operation = async {
        let _admission = lifecycle.enter().await?;
        let programmes = state.programmes.as_ref().map_err(Clone::clone)?;
        let playback = playback.0.as_ref().map_err(Clone::clone)?;

        playback.open(programmes, request).await
    };

    registered
        .run(operation)
        .await
        .map_err(|error| error.reported("open playback"))
}

/// Revokes the session URL, allowing repeated or late closes.
#[tauri::command]
pub fn close_playback(playback: State<'_, PlaybackState>, session_id: String) {
    if let Ok(service) = &playback.0 {
        service.close(&session_id);
    }
}

/// Opens a task's verified download as a cancellable local playback session.
#[tauri::command]
pub async fn open_local_playback(
    state: State<'_, AppState>,
    playback: State<'_, PlaybackState>,
    downloads: State<'_, crate::downloads::DownloadManager>,
    lifecycle: State<'_, Arc<ExitController>>,
    task_id: String,
    request_id: String,
) -> Result<PlaybackSession> {
    let registered = state.requests.register(&request_id)?;
    let operation = async {
        let admission = Arc::new(lifecycle.enter().await?);
        let playback = playback.0.as_ref().map_err(Clone::clone)?;

        let pending = downloads
            .open_local_playback(task_id, playback.clone(), admission)
            .await?;

        Ok(pending.deliver())
    };

    registered
        .run(operation)
        .await
        .map_err(|error| error.reported("open local playback"))
}
