use std::{io, sync::Arc};

use same_file::Handle;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::super::journal::ReservationRecord;
use super::{
    DownloadDirectory, MAX_RECORD_BYTES, Reservation,
    artifacts::{invalid, remove_owned_file},
};

const RECOVERY_RECORD_VERSION: u8 = 1;

#[derive(Deserialize, Serialize)]
pub(super) struct RecoveryRecord {
    #[serde(rename = "sctvDlDownload")]
    version: u8,
    id: String,
}

impl RecoveryRecord {
    pub(super) fn new(id: Uuid) -> Self {
        Self {
            version: RECOVERY_RECORD_VERSION,
            id: id.to_string(),
        }
    }

    fn recognizes(&self, id: &str) -> bool {
        self.version == RECOVERY_RECORD_VERSION && self.id == id && Uuid::parse_str(id).is_ok()
    }
}

impl DownloadDirectory {
    pub(super) fn recover(&self) -> io::Result<()> {
        for entry in std::fs::read_dir(&self.root)? {
            let entry = entry?;
            if !entry.file_type()?.is_file() || entry.metadata()?.len() > MAX_RECORD_BYTES {
                continue;
            }

            let name = entry.file_name();
            let Some(name) = name.to_str() else {
                continue;
            };
            let Some(id) = name
                .strip_prefix(".sctv-dl-")
                .and_then(|name| name.strip_suffix(".json"))
            else {
                continue;
            };
            let Ok(record) =
                serde_json::from_slice::<RecoveryRecord>(&std::fs::read(entry.path())?)
            else {
                continue;
            };
            if !record.recognizes(id) {
                continue;
            }

            // Recovery has no live identity handle. Only recognized records authorize this pair.
            let temporary = self.root.join(format!(".sctv-dl-{id}.part"));
            remove_owned_file(&temporary)?;
            std::fs::remove_file(entry.path())?;
        }

        Ok(())
    }

    /// Reacquires a v2 reservation only after the private index authorizes its identity.
    /// The index checkpoint is authoritative when the journal is ahead after a crash.
    pub fn recover_reservation(
        self: &Arc<Self>,
        record: &ReservationRecord,
    ) -> io::Result<Reservation> {
        record.validate()?;

        let journal = self.root.join(format!(".sctv-dl-{}.json", record.id));
        if !std::fs::symlink_metadata(&journal)?.is_file() {
            return Err(invalid("下载恢复记录已被替换"));
        }

        let disk = crate::storage::read_json::<ReservationRecord>(&journal, MAX_RECORD_BYTES)?
            .ok_or_else(|| invalid("下载恢复记录缺失"))?;
        disk.validate()?;
        if disk.id != record.id
            || disk.checkpoint.task_id != record.checkpoint.task_id
            || disk.checkpoint.attempt_id != record.checkpoint.attempt_id
            || disk.checkpoint.file_identity != record.checkpoint.file_identity
        {
            return Err(invalid("下载恢复记录身份不匹配"));
        }

        let temporary = self.root.join(format!(".sctv-dl-{}.part", record.id));
        let file = record
            .checkpoint
            .file_identity
            .open_verified(&temporary, true)?;
        if file.metadata()?.len() < record.checkpoint.committed_bytes {
            return Err(invalid("下载文件短于已保存的进度"));
        }

        file.set_len(record.checkpoint.committed_bytes)?;
        file.sync_all()?;

        let identity = Handle::from_file(file)?;
        self.reserved
            .lock()
            .unwrap()
            .insert(record.filename.to_lowercase());
        Ok(Reservation {
            directory: self.clone(),
            base: record
                .filename
                .strip_suffix(".mp4")
                .unwrap_or(&record.filename)
                .into(),
            filename: record.filename.clone(),
            temporary,
            journal,
            identity,
            record_bytes: serde_json::to_vec(&disk)?,
            durable: Some(record.clone()),
            retained: false,
        })
    }

    /// Removes a recognized publication journal only after the index records completion.
    pub fn complete_recovered(&self, record: &ReservationRecord) -> io::Result<()> {
        record.validate()?;

        record
            .checkpoint
            .file_identity
            .open_verified(&self.root.join(&record.filename), false)?;

        let journal = self.root.join(format!(".sctv-dl-{}.json", record.id));
        let Some(disk) =
            crate::storage::read_json::<ReservationRecord>(&journal, MAX_RECORD_BYTES)?
        else {
            return Ok(());
        };
        if !std::fs::symlink_metadata(&journal)?.is_file()
            || disk.id != record.id
            || disk.checkpoint.task_id != record.checkpoint.task_id
            || disk.checkpoint.attempt_id != record.checkpoint.attempt_id
            || disk.checkpoint.file_identity != record.checkpoint.file_identity
        {
            return Err(invalid("下载发布记录身份不匹配"));
        }

        let temporary = self.root.join(format!(".sctv-dl-{}.part", record.id));
        match record
            .checkpoint
            .file_identity
            .open_verified(&temporary, false)
        {
            Ok(file) => {
                drop(file);
                std::fs::remove_file(&temporary)?;
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error),
        }

        std::fs::remove_file(&journal)?;
        self.reserved
            .lock()
            .unwrap()
            .remove(&record.filename.to_lowercase());

        Ok(())
    }
}
