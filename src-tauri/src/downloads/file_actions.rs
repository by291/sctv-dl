use super::{manager::Inner, worker::storage, *};
use crate::{
    error::{AppError, ErrorCode, Result},
    lifecycle::OperationGuard,
    media::{PlaybackService, PlaybackSession},
};
use std::{fs::File, path::Path, sync::Arc};

/// Cancels an undelivered local session when its IPC future is dropped.
pub struct PendingLocalPlayback {
    session: Option<PlaybackSession>,
    playback: PlaybackService,
}
impl PendingLocalPlayback {
    pub fn deliver(mut self) -> PlaybackSession {
        self.session.take().unwrap()
    }
}
impl Drop for PendingLocalPlayback {
    fn drop(&mut self) {
        if let Some(session) = &self.session {
            self.playback.close(&session.id);
        }
    }
}

impl DownloadManager {
    pub async fn open_local_playback(
        &self,
        task_id: String,
        playback: PlaybackService,
        operation: Arc<OperationGuard>,
    ) -> Result<PendingLocalPlayback> {
        let admission = self.inner.admission.clone().lock_owned().await;
        let owner = self.inner.clone();
        tokio::task::spawn_blocking(move || {
            let _guards = (operation, admission);
            let (stored, file) = owner.completed_file(&task_id, None)?;
            let session = playback.open_local(task_id, stored.task.quality, file)?;
            Ok(PendingLocalPlayback {
                session: Some(session),
                playback,
            })
        })
        .await
        .map_err(|error| AppError::with_source(ErrorCode::Storage, "本机播放准备异常终止", error))?
    }

    /// File operations are serialized with retries and local session admission.
    pub async fn act_on_file(
        &self,
        request: DownloadActionRequest,
        playback: Option<PlaybackService>,
        operation: Arc<OperationGuard>,
        external: impl FnOnce(&Path, DownloadAction) -> Result<()> + Send + 'static,
    ) -> Result<DownloadActionResult> {
        let owner = self.inner.clone();
        tokio::spawn(async move {
            let admission = owner.admission.clone().lock_owned().await;
            owner.available()?;
            let matches = owner.state.lock().unwrap().entries.iter().any(|entry| {
                entry.stored.task.id == request.task_id
                    && entry.stored.task.attempt_id == request.attempt_id
            });
            if !matches {
                return Ok(DownloadActionResult::Skipped {
                    message: "任务已更新，请刷新后重试".into(),
                });
            }
            if request.action == DownloadAction::DeleteFile
                && let Some(playback) = playback
            {
                playback.close_task(&request.task_id).await;
            }
            tokio::task::spawn_blocking(move || {
                let _guards = (operation, admission);
                let (stored, file) =
                    owner.completed_file(&request.task_id, Some(&request.attempt_id))?;
                let path = stored.directory.join(&stored.task.filename);
                drop(file);
                match request.action {
                    DownloadAction::DeleteFile => {
                        // The directory lock is retained while identity is rechecked and removed.
                        stored
                            .completed_identity
                            .as_ref()
                            .unwrap()
                            .open_verified(&path, false)
                            .map_err(storage)?;
                        std::fs::remove_file(&path).map_err(storage)?;
                        let task = owner.change_blocking(
                            &request.task_id,
                            &request.attempt_id,
                            |record| {
                                record.task.state = TaskState::Missing;
                                record.task.file_available = false;
                                record.task.error = None;
                            },
                        )?;
                        Ok(DownloadActionResult::Applied {
                            task: task.map(Box::new),
                        })
                    }
                    DownloadAction::OpenFile | DownloadAction::RevealFile => {
                        external(&path, request.action)?;
                        Ok(DownloadActionResult::Applied {
                            task: Some(Box::new(stored.task)),
                        })
                    }
                    _ => Err(AppError::new(ErrorCode::InvalidInput, "文件操作无效")),
                }
            })
            .await
            .map_err(|error| AppError::with_source(ErrorCode::Storage, "文件操作异常终止", error))?
        })
        .await
        .map_err(|error| AppError::with_source(ErrorCode::Storage, "文件操作异常终止", error))?
    }
}

impl Inner {
    fn completed_file(
        &self,
        task_id: &str,
        attempt: Option<&str>,
    ) -> Result<(store::StoredTask, File)> {
        self.available()?;
        let stored = {
            let state = self.state.lock().unwrap();
            if !state.accepting {
                return Err(AppError::new(ErrorCode::Cancelled, "应用正在退出"));
            }
            state
                .entries
                .iter()
                .find(|entry| {
                    entry.stored.task.id == task_id
                        && attempt.is_none_or(|attempt| entry.stored.task.attempt_id == attempt)
                })
                .map(|entry| entry.stored.clone())
                .ok_or_else(|| AppError::new(ErrorCode::NotFound, "下载任务不存在或已更新"))?
        };
        if stored.task.state != TaskState::Completed {
            return Err(AppError::new(
                ErrorCode::NotFound,
                "下载文件不可用，请重新下载",
            ));
        }
        let _directory = self.directory(&stored.directory)?;
        let file = stored
            .completed_identity
            .as_ref()
            .ok_or_else(|| AppError::new(ErrorCode::Storage, "下载文件身份缺失"))?
            .open_verified(&stored.directory.join(&stored.task.filename), false);
        match file {
            Ok(file) => Ok((stored, file)),
            Err(error) => {
                let error = storage(error);
                self.change_blocking(&stored.task.id, &stored.task.attempt_id, |record| {
                    record.task.state = TaskState::Missing;
                    record.task.file_available = false;
                    record.task.error = Some("下载文件已丢失或被替换，请重新下载".into());
                })?;
                Err(error)
            }
        }
    }
}
