use std::{io, path::Path, sync::Arc};

use same_file::Handle;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::super::{
    file_identity::{FileAccess, is_missing_or_replaced},
    journal::ReservationRecord,
};
use super::{
    DownloadDirectory, MAX_RECORD_BYTES, Reservation,
    artifacts::{invalid, remove_owned_file, remove_verified_file},
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
        let disk = Self::read_owned_journal(record, &journal)?
            .ok_or_else(|| invalid("Download recovery journal is missing"))?;

        let temporary = self.root.join(format!(".sctv-dl-{}.part", record.id));
        let file = record
            .checkpoint
            .file_identity
            .open_verified(&temporary, FileAccess::ReadWrite)?;
        if file.metadata()?.len() < record.checkpoint.committed_bytes {
            return Err(invalid("Download is shorter than its committed checkpoint"));
        }

        // Data written after the indexed checkpoint is not safe to publish or append to.
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

    /// Finishes cancellation even if an earlier attempt already removed the owned partial.
    pub(in crate::downloads) fn cancel_recovered(
        &self,
        record: &ReservationRecord,
    ) -> io::Result<()> {
        record.validate()?;
        let journal = self.root.join(format!(".sctv-dl-{}.json", record.id));
        let temporary = self.root.join(format!(".sctv-dl-{}.part", record.id));
        let checkpoint = &record.checkpoint;

        // Validate first so a conflicting journal never authorizes deletion. A missing journal
        // is safe here because the private index already records the exact partial identity.
        Self::read_owned_journal(record, &journal)?;
        let remove = remove_verified_file(&temporary, |candidate| {
            checkpoint
                .file_identity
                .open_verified(candidate, FileAccess::ReadOnly)
                .map(drop)
        });
        if let Err(error) = remove
            && !is_missing_or_replaced(&error)
        {
            return Err(error);
        }

        Self::remove_owned_journal(record, &journal)?;
        self.release_name(&record.filename);
        Ok(())
    }

    /// Removes a recognized publication journal only after the index records completion.
    pub fn complete_recovered(&self, record: &ReservationRecord) -> io::Result<()> {
        record.validate()?;

        record
            .checkpoint
            .file_identity
            .open_verified(&self.root.join(&record.filename), FileAccess::ReadOnly)?;

        let journal = self.root.join(format!(".sctv-dl-{}.json", record.id));
        if Self::read_owned_journal(record, &journal)?.is_none() {
            return Ok(());
        }

        let temporary = self.root.join(format!(".sctv-dl-{}.part", record.id));
        let remove = remove_verified_file(&temporary, |candidate| {
            record
                .checkpoint
                .file_identity
                .open_verified(candidate, FileAccess::ReadOnly)
                .map(drop)
        });
        match remove {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error),
        }

        Self::remove_owned_journal(record, &journal)?;
        self.release_name(&record.filename);
        Ok(())
    }

    fn read_owned_journal(
        record: &ReservationRecord,
        journal: &Path,
    ) -> io::Result<Option<ReservationRecord>> {
        match std::fs::symlink_metadata(journal) {
            Ok(metadata) if metadata.is_file() => {}
            Ok(_) => return Err(invalid("Download journal was replaced")),
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error),
        }

        let disk = crate::storage::read_json::<ReservationRecord>(journal, MAX_RECORD_BYTES)?;
        let Some(disk) = disk else {
            return Ok(None);
        };
        disk.validate()?;
        if disk.id != record.id
            || disk.checkpoint.task_id != record.checkpoint.task_id
            || disk.checkpoint.attempt_id != record.checkpoint.attempt_id
            || disk.checkpoint.file_identity != record.checkpoint.file_identity
        {
            return Err(invalid("Download journal identity changed"));
        }

        Ok(Some(disk))
    }

    fn remove_owned_journal(record: &ReservationRecord, journal: &Path) -> io::Result<()> {
        match remove_verified_file(journal, |candidate| {
            Self::read_owned_journal(record, candidate)?
                .map(|_| ())
                .ok_or_else(|| io::ErrorKind::NotFound.into())
        }) {
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            result => result,
        }
    }

    fn release_name(&self, filename: &str) {
        self.reserved
            .lock()
            .unwrap()
            .remove(&filename.to_lowercase());
    }
}
