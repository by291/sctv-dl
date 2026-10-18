use std::sync::{Arc, Mutex};

use super::{MediaConfig, MediaServer, PlaybackSession, Quality};
use crate::{
    error::{AppError, ErrorCode, Result},
    programmes::{ProgrammeService, playback_selection, validate_id},
};

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PlaybackRequest {
    pub programme_id: String,
    pub date_id: String,
    pub content_id: String,
    pub quality: Quality,
}

#[derive(Clone)]
pub struct PlaybackService {
    server: Arc<Mutex<Option<MediaServer>>>,
}

impl PlaybackService {
    pub async fn new(config: MediaConfig) -> Result<Self> {
        Ok(Self {
            server: Arc::new(Mutex::new(Some(MediaServer::bind(config).await?))),
        })
    }

    pub async fn open(
        &self,
        programmes: &ProgrammeService,
        request: PlaybackRequest,
    ) -> Result<PlaybackSession> {
        for id in [&request.programme_id, &request.date_id, &request.content_id] {
            validate_id(id)?;
        }
        if self.server.lock().unwrap().is_none() {
            return Err(service_closed());
        }

        let broadcast = programmes
            .broadcast(&request.programme_id, &request.date_id)
            .await?;
        let content = broadcast
            .contents
            .iter()
            .find(|content| content.id == request.content_id)
            .ok_or_else(|| AppError::new(ErrorCode::NotFound, "节目内容已不可用，请刷新后重试"))?;
        let selection = playback_selection(content, request.quality)
            .ok_or_else(|| AppError::new(ErrorCode::NotFound, "这条内容没有可播放的视频"))?;

        // Preparation does not hold the server lock; shutdown may have taken ownership meanwhile.
        let server = self.server.lock().unwrap();
        server
            .as_ref()
            .ok_or_else(service_closed)?
            .open(selection.sources, selection.selected_quality)
    }

    pub fn open_local(
        &self,
        task_id: String,
        quality: Quality,
        file: std::fs::File,
    ) -> Result<PlaybackSession> {
        self.server
            .lock()
            .unwrap()
            .as_ref()
            .ok_or_else(service_closed)?
            .open_local(task_id, quality, file)
    }

    /// Revokes local URLs and waits for every admitted read, even after URL close
    /// or cancellation of a previous close_task waiter. File deletion follows this.
    pub async fn close_task(&self, task_id: &str) {
        let producers = self
            .server
            .lock()
            .unwrap()
            .as_ref()
            .map(|server| server.close_task(task_id))
            .unwrap_or_default();

        for producer in producers {
            producer.wait().await;
        }
    }

    pub fn close(&self, id: &str) {
        if let Some(server) = self.server.lock().unwrap().as_ref() {
            server.close(id);
        }
    }

    /// Prevents new sessions and awaits every connection and local/upstream producer.
    pub async fn shutdown(&self) {
        let server = { self.server.lock().unwrap().take() };
        if let Some(server) = server {
            server.shutdown().await;
        }
    }
}

fn service_closed() -> AppError {
    AppError::new(ErrorCode::Cancelled, "视频服务已关闭")
}
