use super::{
    manager::{Control, Inner, Job},
    worker::storage,
    *,
};
use crate::{
    error::{AppError, ErrorCode, Result},
    lifecycle::OperationGuard,
    media::policy,
};
use std::sync::Arc;
use uuid::Uuid;

impl DownloadManager {
    /// Owns the action after dispatch so IPC cancellation cannot release exit admission early.
    pub async fn act(
        &self,
        request: DownloadActionRequest,
        prepared: Option<PreparedDownload>,
        operation: Arc<OperationGuard>,
    ) -> Result<DownloadActionResult> {
        let owner = self.inner.clone();
        tokio::spawn(async move {
            let _operation = operation;
            owner.act(request, prepared).await
        })
        .await
        .map_err(|error| AppError::with_source(ErrorCode::Storage, "下载操作异常终止", error))?
    }

    pub fn task(&self, id: &str) -> Result<DownloadTask> {
        self.inner.available()?;
        self.list()
            .into_iter()
            .find(|task| task.id == id)
            .ok_or_else(|| AppError::new(ErrorCode::NotFound, "下载任务不存在"))
    }
}

impl Inner {
    async fn act(
        self: &Arc<Self>,
        request: DownloadActionRequest,
        prepared: Option<PreparedDownload>,
    ) -> Result<DownloadActionResult> {
        self.available()?;
        let _admission = self.admission.lock().await;
        let (stored, control) = {
            let state = self.state.lock().unwrap();
            if !state.accepting {
                return Err(AppError::new(ErrorCode::Cancelled, "应用正在退出"));
            }
            let Some(entry) = state.entries.iter().find(|entry| {
                entry.stored.task.id == request.task_id
                    && entry.stored.task.attempt_id == request.attempt_id
            }) else {
                return Ok(skipped("任务已更新，请刷新后重试"));
            };
            (entry.stored.clone(), entry.control.clone())
        };
        if matches!(
            request.action,
            DownloadAction::Pause | DownloadAction::Cancel
        ) && stored.task.active()
        {
            let owner = self.clone();
            let task_id = request.task_id.clone();
            let attempt_id = request.attempt_id.clone();
            let intent = if request.action == DownloadAction::Pause {
                StopIntent::Pause
            } else {
                StopIntent::Cancel
            };
            let admitted = tokio::task::spawn_blocking(move || {
                owner.request_stop(&task_id, &attempt_id, intent)
            })
            .await
            .map_err(|error| {
                AppError::with_source(ErrorCode::Storage, "下载停止请求异常终止", error)
            })?;
            if !admitted {
                return Ok(skipped("任务正在保存或已经停止，请稍后重试"));
            }
            control.wait().await;
            let task = self
                .state
                .lock()
                .unwrap()
                .entries
                .iter()
                .find(|entry| entry.stored.task.id == request.task_id)
                .map(|entry| entry.stored.task.clone());
            if let Some(task) = &task
                && task.state == TaskState::Failed
            {
                return Err(AppError::new(
                    ErrorCode::Storage,
                    task.error.clone().unwrap_or_else(|| "下载操作失败".into()),
                ));
            }
            return Ok(DownloadActionResult::Applied {
                task: task.map(Box::new),
            });
        }
        if stored.task.active() {
            return Ok(skipped("任务仍在处理中，请稍后重试"));
        }
        let owner = self.clone();
        tokio::task::spawn_blocking(move || owner.act_settled(request, prepared, stored))
            .await
            .map_err(|error| AppError::with_source(ErrorCode::Storage, "下载操作异常终止", error))?
    }

    pub(super) fn request_stop(&self, id: &str, attempt: &str, intent: StopIntent) -> bool {
        // Serialize the stop decision with the worker's finalization transition.
        let _writer = self.writes.lock().unwrap();
        let changed = {
            let mut state = self.state.lock().unwrap();
            let Some(entry) = state.entries.iter_mut().find(|entry| {
                entry.stored.task.id == id
                    && entry.stored.task.attempt_id == attempt
                    && matches!(
                        entry.stored.task.state,
                        TaskState::Queued | TaskState::Running
                    )
            }) else {
                return false;
            };
            entry.control.stop(intent);
            if intent == StopIntent::Pause {
                entry.stored.task.state = TaskState::Pausing;
            }
            entry.stored.task.revision += 1;
            let task = entry.stored.task.clone();
            state.revision += 1;
            (task, state.revision)
        };
        self.emit(changed.0, changed.1);
        true
    }

    fn act_settled(
        &self,
        request: DownloadActionRequest,
        prepared: Option<PreparedDownload>,
        stored: store::StoredTask,
    ) -> Result<DownloadActionResult> {
        match request.action {
            DownloadAction::Pause => Ok(skipped("任务已经停止")),
            DownloadAction::Remove => {
                if stored.task.has_partial {
                    return Ok(skipped("请先取消并清理临时数据，再移除记录"));
                }
                let _writer = self.writes.lock().unwrap();
                let (records, revision) = {
                    let state = self.state.lock().unwrap();
                    (
                        state
                            .entries
                            .iter()
                            .filter(|entry| entry.stored.task.id != request.task_id)
                            .map(|entry| entry.stored.clone())
                            .collect(),
                        state.revision + 1,
                    )
                };
                let persisted = self.save(records, revision);
                if let Err(error) = &persisted
                    && !store::replacement_committed(error)
                {
                    return Err(error.clone());
                }
                let revision = {
                    let mut state = self.state.lock().unwrap();
                    state
                        .entries
                        .retain(|entry| entry.stored.task.id != request.task_id);
                    state.revision += 1;
                    state.revision
                };
                self.emit_event(DownloadEvent::Remove {
                    epoch: self.epoch.clone(),
                    revision,
                    task_id: request.task_id,
                });
                persisted?;
                Ok(DownloadActionResult::Applied { task: None })
            }
            DownloadAction::Cancel => {
                if !stored.task.has_partial {
                    return Ok(skipped("任务没有待清理的临时数据"));
                }
                let directory = self.directory(&stored.directory)?;
                let reservation = stored
                    .reservation
                    .as_ref()
                    .ok_or_else(|| AppError::new(ErrorCode::Storage, "下载恢复信息缺失"))?;
                directory
                    .recover_reservation(reservation)
                    .map_err(storage)?
                    .cleanup()
                    .map_err(storage)?;
                let task =
                    self.change_blocking(&request.task_id, &request.attempt_id, |record| {
                        record.reservation = None;
                        record.task.has_partial = false;
                        record.task.can_resume = false;
                        record.task.state = TaskState::Cancelled;
                        record.task.error = None;
                    })?;
                Ok(DownloadActionResult::Applied {
                    task: task.map(Box::new),
                })
            }
            DownloadAction::Resume | DownloadAction::Restart => {
                self.restart(request, prepared, stored)
            }
            DownloadAction::DeleteFile | DownloadAction::OpenFile | DownloadAction::RevealFile => {
                Err(AppError::new(
                    ErrorCode::InvalidInput,
                    "文件操作需要本机应用处理",
                ))
            }
        }
    }

    fn restart(
        &self,
        request: DownloadActionRequest,
        prepared: Option<PreparedDownload>,
        stored: store::StoredTask,
    ) -> Result<DownloadActionResult> {
        let resume = request.action == DownloadAction::Resume;
        if !matches!(
            stored.task.state,
            TaskState::Paused
                | TaskState::Interrupted
                | TaskState::Failed
                | TaskState::Cancelled
                | TaskState::Missing
        ) {
            return Ok(skipped("当前任务状态不允许重新下载"));
        }
        if resume && !stored.task.can_resume {
            return Ok(skipped("该下载不能安全续传，请重新下载"));
        }
        let file =
            prepared.ok_or_else(|| AppError::new(ErrorCode::NotFound, "节目来源已不可用"))?;
        policy::target(&file.url, &self.origins)?;
        if file.content != stored.task.content || resume && file.quality != stored.task.quality {
            return Err(AppError::new(
                ErrorCode::Upstream,
                "视频清晰度或来源已改变，请重新下载",
            ));
        }
        if self.state.lock().unwrap().entries.iter().any(|entry| {
            entry.stored.task.id != stored.task.id
                && entry.stored.task.unfinished()
                && entry.stored.task.content == file.content
                && entry.stored.task.quality == file.quality
                && entry.stored.directory == stored.directory
        }) {
            return Ok(skipped("相同节目、清晰度和目录已有未完成的任务"));
        }
        if !stored.task.unfinished()
            && self
                .state
                .lock()
                .unwrap()
                .entries
                .iter()
                .filter(|entry| entry.stored.task.unfinished())
                .count()
                >= self.config.queue_capacity + 2
        {
            return Ok(skipped("下载队列已满，请稍后重试"));
        }
        let permit = self
            .send
            .try_reserve()
            .map_err(|_| AppError::new(ErrorCode::InvalidInput, "下载队列已满，请稍后重试"))?;
        let directory = self.directory(&stored.directory)?;
        let attempt = Uuid::new_v4().to_string();
        let (mut reservation, record) = if resume {
            let previous = stored
                .reservation
                .as_ref()
                .ok_or_else(|| AppError::new(ErrorCode::Storage, "下载恢复信息缺失"))?;
            let mut reservation = directory.recover_reservation(previous).map_err(storage)?;
            let record = match reservation.new_attempt(attempt.clone()) {
                Ok(record) => record,
                Err(error) => {
                    let _ = reservation.new_attempt(request.attempt_id.clone());
                    reservation.retain();
                    return Err(storage(error));
                }
            };
            (reservation, record)
        } else {
            if let Some(previous) = &stored.reservation
                && stored.task.has_partial
            {
                directory
                    .recover_reservation(previous)
                    .map_err(storage)?
                    .cleanup()
                    .map_err(storage)?;
                self.change_blocking(&request.task_id, &request.attempt_id, |record| {
                    record.reservation = None;
                    record.task.has_partial = false;
                    record.task.can_resume = false;
                    record.task.state = TaskState::Cancelled;
                })?;
            }
            let (writer, mut reservation) = directory.reserve(&file.filename).map_err(storage)?;
            drop(writer);
            let record = match reservation.upgrade(request.task_id.clone(), attempt.clone()) {
                Ok(record) => record,
                Err(error) => {
                    reservation.cleanup().map_err(storage)?;
                    return Err(storage(error));
                }
            };
            (reservation, record)
        };
        let saved = self.change_blocking(&request.task_id, &request.attempt_id, |stored| {
            stored.task.attempt_id = attempt.clone();
            stored.task.state = TaskState::Queued;
            stored.task.filename = record.filename.clone();
            stored.task.quality = file.quality;
            stored.task.metadata = file.metadata;
            stored.task.received_bytes = record.checkpoint.committed_bytes;
            stored.task.total_bytes = record.checkpoint.total_bytes;
            stored.task.error = None;
            stored.task.has_partial = true;
            stored.task.file_available = false;
            stored.task.can_resume = record.checkpoint.resumable();
            stored.completed_identity = None;
            stored.reservation = Some(record.clone());
        });
        let task = match saved {
            Ok(task) => task,
            Err(error) => {
                if store::replacement_committed(&error) {
                    reservation.retain();
                    self.report_failure(&request.task_id, &attempt, error.clone());
                } else if resume {
                    let _ = reservation.new_attempt(request.attempt_id);
                    reservation.retain();
                } else {
                    reservation.cleanup().map_err(storage)?;
                }
                return Err(error);
            }
        };
        let control = Control::new(false);
        if let Some(entry) = self
            .state
            .lock()
            .unwrap()
            .entries
            .iter_mut()
            .find(|entry| entry.stored.task.id == request.task_id)
        {
            entry.control = control.clone();
        }
        permit.send(Job {
            id: request.task_id,
            attempt,
            url: file.url,
            reservation,
            control,
            checkpoint: record.checkpoint,
            resume,
        });
        Ok(DownloadActionResult::Applied {
            task: task.map(Box::new),
        })
    }
}

fn skipped(message: &str) -> DownloadActionResult {
    DownloadActionResult::Skipped {
        message: message.into(),
    }
}
