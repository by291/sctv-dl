use std::sync::Mutex;

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

pub struct PlaybackService {
    server: Mutex<Option<MediaServer>>,
}

impl PlaybackService {
    pub async fn new(config: MediaConfig) -> Result<Self> {
        Ok(Self {
            server: Mutex::new(Some(MediaServer::bind(config).await?)),
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

    pub fn close(&self, id: &str) {
        if let Some(server) = self.server.lock().unwrap().as_ref() {
            server.close(id);
        }
    }

    /// Prevents new sessions and awaits every connection and upstream producer.
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
