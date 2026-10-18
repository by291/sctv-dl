use super::{TaskState, errors::storage, journal, manager::Inner};
use crate::error::{AppError, ErrorCode, Result};

pub(super) fn recover(owner: &Inner) {
    let records = owner.records.records();
    for mut record in records {
        let recovered = recover_record(owner, &mut record);
        if let Err(error) = recovered {
            record.task.state = if record.completed_identity.is_some() {
                TaskState::Missing
            } else {
                TaskState::Failed
            };
            record.task.file_available = false;
            record.task.can_resume = false;
            record.task.error = Some(error.reported("recover download").message);
        }

        let id = record.task.id.clone();
        let attempt = record.task.attempt_id.clone();
        let publication = (record.task.state == TaskState::Completed)
            .then(|| record.reservation.clone())
            .flatten();
        let directory = record.directory.clone();

        match owner
            .records
            .change_blocking(&id, &attempt, |entry| *entry = record)
        {
            Ok(_) => {
                if let Some(publication) = publication
                    && let Err(error) = owner.directory(&directory).and_then(|directory| {
                        directory.complete_recovered(&publication).map_err(storage)
                    })
                {
                    owner.records.report_failure(&id, &attempt, error);
                }
            }
            Err(error) => owner.records.report_failure(&id, &attempt, error),
        }
    }
}

fn recover_record(owner: &Inner, record: &mut super::store::StoredTask) -> Result<()> {
    if record.task.state == TaskState::Completed || record.completed_identity.is_some() {
        let identity = record
            .completed_identity
            .as_ref()
            .ok_or_else(|| AppError::new(ErrorCode::Storage, "下载文件身份缺失"))?;
        identity
            .open_verified(&record.directory.join(&record.task.filename), false)
            .map_err(storage)?;

        record.task.state = TaskState::Completed;
        record.task.file_available = true;
        record.task.has_partial = false;
        record.task.can_resume = false;
        record.task.error = None;
        return Ok(());
    }

    if !record.task.unfinished() {
        return Ok(());
    }

    let directory = owner.directory(&record.directory)?;
    if let Some(reservation) = &record.reservation {
        if reservation.phase != journal::PublicationPhase::Writing
            && let Ok(file) = reservation
                .checkpoint
                .file_identity
                .open_verified(&record.directory.join(&reservation.filename), false)
            && file.metadata().map_err(storage)?.len() == reservation.checkpoint.committed_bytes
        {
            record.task.filename = reservation.filename.clone();
            record.task.state = TaskState::Completed;
            record.task.received_bytes = reservation.checkpoint.committed_bytes;
            record.task.file_available = true;
            record.task.has_partial = false;
            record.task.can_resume = false;
            record.completed_identity = Some(reservation.checkpoint.file_identity.clone());
            return Ok(());
        }

        directory
            .recover_reservation(reservation)
            .map_err(storage)?
            .retain();
        record.task.received_bytes = reservation.checkpoint.committed_bytes;
        record.task.total_bytes = reservation.checkpoint.total_bytes;
        record.task.can_resume = reservation.checkpoint.resumable();
        record.task.has_partial = true;
    }

    record.task.state = TaskState::Interrupted;
    Ok(())
}
