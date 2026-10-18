use std::sync::Arc;

use uuid::Uuid;

use super::{
    errors::{storage, with_rollback},
    manager::{Control, Inner, Job},
    records::Admission,
    *,
};
use crate::{
    error::{AppError, ErrorCode, Result},
    lifecycle::OperationGuard,
    media::policy,
};

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
        self.inner.records.available()?;
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
        self.records.available()?;

        let _admission = self.admission.lock().await;
        if !self.records.accepting() {
            return Err(AppError::new(ErrorCode::Cancelled, "应用正在退出"));
        }
        let Some((stored, control)) = self
            .records
            .find(&request.task_id, Some(&request.attempt_id))
        else {
            return Ok(skipped("任务已更新，请刷新后重试"));
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
                owner.records.request_stop(&task_id, &attempt_id, intent)
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
                .records
                .find(&request.task_id, None)
                .map(|(stored, _)| stored.task);
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

                self.records.remove(&request.task_id)?;
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

                let task = self.records.change_blocking(
                    &request.task_id,
                    &request.attempt_id,
                    |record| {
                        record.reservation = None;
                        record.task.has_partial = false;
                        record.task.can_resume = false;
                        record.task.state = TaskState::Cancelled;
                        record.task.error = None;
                    },
                )?;
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

    pub(super) fn restart(
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

        match self.records.admission(
            &file,
            &stored.directory,
            Some(&stored.task.id),
            self.config.queue_capacity,
        ) {
            Ok(Admission::Available) => {}
            Ok(Admission::Duplicate(_)) => {
                return Ok(skipped("相同节目、清晰度和目录已有未完成的任务"));
            }
            Err(error) if error.code == ErrorCode::InvalidInput => {
                return Ok(skipped(&error.message));
            }
            Err(error) => return Err(error),
        }

        let permit = self
            .send
            .try_reserve()
            .map_err(|_| AppError::new(ErrorCode::InvalidInput, "下载队列已满，请稍后重试"))?;
        let directory = self.directory(&stored.directory)?;
        let attempt = Uuid::new_v4().to_string();
        let (mut reservation, record) = if resume {
            resume_reservation(&directory, &stored, &attempt)?
        } else {
            self.restart_reservation(&directory, &stored, &file.filename, &attempt)?
        };

        // Keep the reservation alive until the new attempt owns it in the task index.
        let saved = self
            .records
            .change_blocking(&request.task_id, &request.attempt_id, |stored| {
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
                    self.records
                        .report_failure(&request.task_id, &attempt, error.clone());
                } else if resume {
                    let rollback = reservation
                        .new_attempt(request.attempt_id)
                        .map(|_| ())
                        .map_err(storage);
                    reservation.retain();
                    return Err(with_rollback(error, rollback));
                } else {
                    return Err(with_rollback(error, reservation.cleanup().map_err(storage)));
                }
                return Err(error);
            }
        };

        let control = Control::new(false);
        self.records
            .replace_control(&request.task_id, control.clone());

        // The new attempt and its cancellation owner are installed before the dispatcher sees it.
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

    fn restart_reservation(
        &self,
        directory: &Arc<super::files::DownloadDirectory>,
        stored: &store::StoredTask,
        filename: &str,
        attempt: &str,
    ) -> Result<(super::files::Reservation, journal::ReservationRecord)> {
        if let Some(previous) = &stored.reservation
            && stored.task.has_partial
        {
            directory
                .recover_reservation(previous)
                .map_err(storage)?
                .cleanup()
                .map_err(storage)?;
            self.records
                .change_blocking(&stored.task.id, &stored.task.attempt_id, |record| {
                    record.reservation = None;
                    record.task.has_partial = false;
                    record.task.can_resume = false;
                    record.task.state = TaskState::Cancelled;
                })?;
        }

        let (writer, mut reservation) = directory.reserve(filename).map_err(storage)?;
        drop(writer);

        let record = match reservation.upgrade(stored.task.id.clone(), attempt.to_owned()) {
            Ok(record) => record,
            Err(error) => {
                return Err(with_rollback(
                    storage(error),
                    reservation.cleanup().map_err(storage),
                ));
            }
        };
        Ok((reservation, record))
    }
}

fn skipped(message: &str) -> DownloadActionResult {
    DownloadActionResult::Skipped {
        message: message.into(),
    }
}

fn resume_reservation(
    directory: &Arc<super::files::DownloadDirectory>,
    stored: &store::StoredTask,
    attempt: &str,
) -> Result<(super::files::Reservation, journal::ReservationRecord)> {
    let previous = stored
        .reservation
        .as_ref()
        .ok_or_else(|| AppError::new(ErrorCode::Storage, "下载恢复信息缺失"))?;

    let mut reservation = directory.recover_reservation(previous).map_err(storage)?;
    let record = match reservation.new_attempt(attempt.to_owned()) {
        Ok(record) => record,
        Err(error) => {
            let rollback = reservation
                .new_attempt(stored.task.attempt_id.clone())
                .map(|_| ())
                .map_err(storage);
            reservation.retain();
            return Err(with_rollback(storage(error), rollback));
        }
    };
    Ok((reservation, record))
}
