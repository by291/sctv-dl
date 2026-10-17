use std::sync::Arc;

use tauri::{AppHandle, Runtime};

use crate::{
    downloads::{DownloadManager, DownloadRequest, DownloadStart},
    error::Result,
    lifecycle::ExitController,
    settings::DesktopSettings,
    state::AppState,
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
