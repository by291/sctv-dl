use std::sync::Arc;

use tauri::State;

use crate::{
    error::Result,
    lifecycle::ExitController,
    media::{PlaybackRequest, PlaybackSession},
    state::{AppState, PlaybackState},
};

#[tauri::command]
pub async fn open_playback(
    state: State<'_, AppState>,
    playback: State<'_, PlaybackState>,
    lifecycle: State<'_, Arc<ExitController>>,
    request: PlaybackRequest,
    request_id: String,
) -> Result<PlaybackSession> {
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
        .map_err(|error| error.reported("open playback"))
}

#[tauri::command]
pub fn close_playback(playback: State<'_, PlaybackState>, session_id: String) {
    if let Ok(service) = &playback.0 {
        service.close(&session_id);
    }
}

#[tauri::command]
pub async fn open_local_playback(
    state: State<'_, AppState>,
    playback: State<'_, PlaybackState>,
    downloads: State<'_, crate::downloads::DownloadManager>,
    lifecycle: State<'_, Arc<ExitController>>,
    task_id: String,
    request_id: String,
) -> Result<PlaybackSession> {
    state
        .requests
        .register(&request_id)?
        .run(async {
            let operation = Arc::new(lifecycle.enter().await?);
            let playback = playback.0.as_ref().map_err(Clone::clone)?.clone();
            let pending = downloads
                .open_local_playback(task_id, playback, operation)
                .await?;
            Ok(pending.deliver())
        })
        .await
        .map_err(|error| error.reported("open local playback"))
}
