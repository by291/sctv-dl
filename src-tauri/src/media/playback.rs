use std::sync::Mutex;

use super::{MediaConfig, MediaServer, MediaSource, PlaybackSession, Quality};
use crate::{
    error::{AppError, Result},
    programmes::{ProgrammeService, validate_id},
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
            return Err(AppError::new("cancelled", "视频服务已关闭"));
        }
        let dates = programmes.dates(&request.programme_id).await?;
        if !dates.iter().any(|date| date.id == request.date_id) {
            return Err(AppError::new("not-found", "播出日期已不可用，请刷新后重试"));
        }
        let contents = programmes
            .contents(&request.programme_id, &request.date_id)
            .await?;
        let content = contents
            .iter()
            .find(|content| content.id == request.content_id)
            .ok_or_else(|| AppError::new("not-found", "节目内容已不可用，请刷新后重试"))?;
        let mut sources = Vec::new();
        if let Some(url) = &content.video {
            sources.push(MediaSource {
                quality: Quality::Standard,
                url: url.clone(),
            });
        }
        if let Some(url) = &content.smooth_video
            && !sources.iter().any(|source| &source.url == url)
        {
            sources.push(MediaSource {
                quality: Quality::Smooth,
                url: url.clone(),
            });
        }
        let selected = sources
            .iter()
            .find(|source| source.quality == request.quality)
            .or_else(|| sources.first())
            .ok_or_else(|| AppError::new("not-found", "这条内容没有可播放的视频"))?
            .quality;
        self.server
            .lock()
            .unwrap()
            .as_ref()
            .ok_or_else(|| AppError::new("cancelled", "视频服务已关闭"))?
            .open(sources, selected)
    }

    pub fn close(&self, id: &str) {
        if let Some(server) = self.server.lock().unwrap().as_ref() {
            server.close(id);
        }
    }

    pub async fn shutdown(&self) {
        let server = self.server.lock().unwrap().take();
        if let Some(server) = server {
            server.shutdown().await;
        }
    }
}
