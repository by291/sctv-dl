use std::sync::{Arc, Mutex};

use futures_util::{
    FutureExt,
    future::{BoxFuture, Shared},
};

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
    state: Arc<Mutex<ServerState>>,
}

enum ServerState {
    Running(MediaServer),
    Closing(Shared<BoxFuture<'static, ()>>),
}

impl ServerState {
    fn running(&self) -> Result<&MediaServer> {
        match self {
            Self::Running(server) => Ok(server),
            Self::Closing(_) => Err(service_closed()),
        }
    }
}

impl PlaybackService {
    /// Starts the private media listener for this application.
    pub async fn new(config: MediaConfig) -> Result<Self> {
        Ok(Self::own(MediaServer::bind(config).await?))
    }

    pub(super) fn own(server: MediaServer) -> Self {
        Self {
            state: Arc::new(Mutex::new(ServerState::Running(server))),
        }
    }

    /// Resolves a content reference and publishes its validated online sources.
    pub async fn open(
        &self,
        programmes: &ProgrammeService,
        request: PlaybackRequest,
    ) -> Result<PlaybackSession> {
        for id in [&request.programme_id, &request.date_id, &request.content_id] {
            validate_id(id)?;
        }
        self.state.lock().unwrap().running()?;

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
        let state = self.state.lock().unwrap();
        let server = state.running()?;

        server.open(selection.sources, selection.selected_quality)
    }

    /// Publishes a verified open file as an opaque local playback session.
    pub fn open_local(
        &self,
        task_id: String,
        quality: Quality,
        file: std::fs::File,
    ) -> Result<PlaybackSession> {
        let state = self.state.lock().unwrap();
        let server = state.running()?;

        server.open_local(task_id, quality, file)
    }

    /// Revokes local URLs and waits for every admitted read, even after URL close
    /// or cancellation of a previous close_task waiter. File deletion follows this.
    pub async fn close_task(&self, task_id: &str) {
        let (producers, shutdown) = {
            let state = self.state.lock().unwrap();
            match &*state {
                ServerState::Running(server) => (server.close_task(task_id), None),
                ServerState::Closing(shutdown) => (Vec::new(), Some(shutdown.clone())),
            }
        };

        if let Some(shutdown) = shutdown {
            shutdown.await;
            return;
        }

        for producer in producers {
            producer.wait().await;
        }
    }

    /// Revokes one URL and signals cancellation without waiting for admitted reads.
    pub fn close(&self, id: &str) {
        if let Ok(server) = self.state.lock().unwrap().running() {
            server.close(id);
        }
    }

    /// Prevents new sessions and awaits every connection and local/upstream producer.
    pub async fn shutdown(&self) {
        let completion = {
            let mut state = self.state.lock().unwrap();
            if let ServerState::Closing(completion) = &*state {
                completion.clone()
            } else {
                start_shutdown(&mut state)
            }
        };

        completion.await;
    }
}

fn start_shutdown(state: &mut ServerState) -> Shared<BoxFuture<'static, ()>> {
    let (transfer, server) = tokio::sync::oneshot::channel::<MediaServer>();
    let worker = tokio::spawn(async move {
        if let Ok(server) = server.await {
            server.shutdown().await;
        }
    });
    let completion = async move {
        if let Err(error) = worker.await {
            AppError::with_source(ErrorCode::Upstream, "视频服务关闭异常终止", error)
                .reported("close native playback service");
        }
    }
    .boxed()
    .shared();

    // Store the same join future for every caller before transferring the server to its owner.
    let previous = std::mem::replace(state, ServerState::Closing(completion.clone()));
    if let ServerState::Running(server) = previous {
        let _ = transfer.send(server);
    }

    completion
}

fn service_closed() -> AppError {
    AppError::new(ErrorCode::Cancelled, "视频服务已关闭")
}
