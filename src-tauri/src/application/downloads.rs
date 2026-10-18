use std::sync::Arc;

use tauri::{AppHandle, Runtime};

use crate::{
    downloads::{
        DownloadAction, DownloadActionRequest, DownloadActionResult, DownloadManager,
        DownloadRequest, DownloadStart, PreparedDownload,
    },
    error::{AppError, ErrorCode, Result},
    lifecycle::ExitController,
    settings::DesktopSettings,
    state::{AppState, PlaybackState},
};

#[derive(serde::Serialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum DownloadResult {
    Cancelled,
    Native(DownloadStart),
}

/// Coordinates content preparation, directory selection, and task admission.
pub struct DownloadService<'a, R: Runtime> {
    state: &'a AppState,
    settings: &'a DesktopSettings<R>,
    downloads: &'a DownloadManager,
    lifecycle: &'a ExitController,
}

impl<'a, R: Runtime> DownloadService<'a, R> {
    pub fn new(
        state: &'a AppState,
        settings: &'a DesktopSettings<R>,
        downloads: &'a DownloadManager,
        lifecycle: &'a ExitController,
    ) -> Self {
        Self {
            state,
            settings,
            downloads,
            lifecycle,
        }
    }

    pub async fn start(
        &self,
        app: &AppHandle<R>,
        request: DownloadRequest,
    ) -> Result<DownloadResult> {
        let operation = Arc::new(self.lifecycle.enter().await?);
        let service = self.state.programmes.as_ref().map_err(Clone::clone)?;
        let quality = request.quality;

        let prepared = self.downloads.prepare(service, request).await?;
        if prepared.files.is_empty() {
            return Ok(DownloadResult::Native(DownloadStart {
                failures: prepared.failures,
                ..DownloadStart::default()
            }));
        }

        let Some(path) = self
            .settings
            .ensure_download_directory(app, operation.clone())
            .await?
        else {
            return Ok(DownloadResult::Cancelled);
        };

        let mut result = self
            .downloads
            .start_owned(prepared.files, &path, Some(operation))
            .await?;
        result.failures.extend(prepared.failures);
        result.used_fallback = self
            .downloads
            .list()
            .iter()
            .any(|task| result.task_ids.contains(&task.id) && task.quality != quality);

        Ok(DownloadResult::Native(result))
    }
}

/// Owns lifecycle admission, source refresh, and routing for existing task actions.
pub struct DownloadActionService<'a> {
    state: &'a AppState,
    downloads: &'a DownloadManager,
    playback: &'a PlaybackState,
    lifecycle: &'a ExitController,
}

impl<'a> DownloadActionService<'a> {
    pub fn new(
        state: &'a AppState,
        downloads: &'a DownloadManager,
        playback: &'a PlaybackState,
        lifecycle: &'a ExitController,
    ) -> Self {
        Self {
            state,
            downloads,
            playback,
            lifecycle,
        }
    }

    pub async fn act<R: Runtime>(
        &self,
        app: AppHandle<R>,
        request: DownloadActionRequest,
    ) -> Result<DownloadActionResult> {
        // Retain admission through source refresh and transfer it to the action owner.
        let operation = Arc::new(self.lifecycle.enter().await?);
        let task = self.downloads.task(&request.task_id)?;
        if task.attempt_id != request.attempt_id {
            return Ok(DownloadActionResult::Skipped {
                message: "任务已更新，请刷新后重试".into(),
            });
        }

        if matches!(
            request.action,
            DownloadAction::DeleteFile | DownloadAction::OpenFile | DownloadAction::RevealFile
        ) {
            return super::download_files::act_on_file(
                app,
                self.downloads,
                self.playback.0.as_ref().ok().cloned(),
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
            Some(self.refresh_source(task).await?)
        } else {
            None
        };

        // The manager checks the attempt again after potentially slow metadata work.
        self.downloads
            .act(request, prepared, operation)
            .await
            .map_err(|error| error.reported("download action"))
    }

    async fn refresh_source(
        &self,
        task: crate::downloads::DownloadTask,
    ) -> Result<PreparedDownload> {
        let service = self.state.programmes.as_ref().map_err(Clone::clone)?;

        let mut batch = self
            .downloads
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

        batch
            .files
            .pop()
            .ok_or_else(|| AppError::new(ErrorCode::NotFound, "节目视频来源已不可用"))
    }
}
