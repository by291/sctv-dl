use std::{fs::File, io, path::PathBuf, sync::Arc};

use same_file::Handle;
use tempfile::TempPath;

use super::super::{
    file_identity::FileIdentity,
    journal::{PublicationPhase, ReservationRecord, ResumeCheckpoint},
};
use super::{
    DownloadDirectory, MAX_RECORD_BYTES,
    artifacts::{combine, invalid, remove_identified_file, verify_identity},
};

pub struct Reservation {
    pub(super) directory: Arc<DownloadDirectory>,
    pub(super) base: String,
    pub(super) filename: String,
    pub(super) temporary: PathBuf,
    pub(super) journal: PathBuf,
    pub(super) identity: Handle,
    pub(super) record_bytes: Vec<u8>,
    pub(super) durable: Option<ReservationRecord>,
    pub(super) retained: bool,
}

impl Reservation {
    pub fn filename(&self) -> &str {
        &self.filename
    }

    pub(crate) fn writer(&self) -> io::Result<File> {
        self.identity.as_file().try_clone()
    }

    pub fn upgrade(
        &mut self,
        task_id: String,
        attempt_id: String,
    ) -> io::Result<ReservationRecord> {
        self.identity.as_file().sync_all()?;

        let record = ReservationRecord {
            sctv_dl_download: 2,
            id: self
                .journal
                .file_stem()
                .unwrap()
                .to_string_lossy()
                .trim_start_matches(".sctv-dl-")
                .into(),
            filename: self.filename.clone(),
            checkpoint: ResumeCheckpoint {
                task_id,
                attempt_id,
                file_identity: FileIdentity::read(self.identity.as_file())?,
                committed_bytes: 0,
                total_bytes: None,
                etag: None,
            },
            phase: PublicationPhase::Writing,
        };
        self.save_record(record)
    }

    fn save_record(&mut self, record: ReservationRecord) -> io::Result<ReservationRecord> {
        #[cfg(test)]
        super::RECORD_WRITE_HOOK.with(|hook| {
            if let Some(hook) = hook.borrow_mut().take() {
                hook(&self.journal);
            }
        });

        let saved = crate::storage::write_json_atomic(&self.journal, &record);
        if saved.is_ok()
            || saved
                .as_ref()
                .is_err_and(crate::storage::replacement_committed)
        {
            self.record_bytes = serde_json::to_vec(&record)?;
            self.durable = Some(record.clone());
        }

        saved?;
        Ok(record)
    }

    pub fn checkpoint(
        &mut self,
        bytes: u64,
        total: Option<u64>,
        etag: Option<String>,
    ) -> io::Result<ReservationRecord> {
        verify_identity(&self.temporary, &self.identity)?;
        if self.identity.as_file().metadata()?.len() < bytes {
            return Err(invalid("下载文件短于待保存的进度"));
        }

        self.identity.as_file().sync_all()?;
        let mut record = self
            .durable
            .clone()
            .ok_or_else(|| invalid("下载没有持久化恢复记录"))?;
        record.checkpoint.committed_bytes = bytes;
        record.checkpoint.total_bytes = total;
        record.checkpoint.etag = etag;
        self.save_record(record)
    }

    pub fn new_attempt(&mut self, attempt_id: String) -> io::Result<ReservationRecord> {
        let mut record = self
            .durable
            .clone()
            .ok_or_else(|| invalid("下载没有持久化恢复记录"))?;
        record.checkpoint.attempt_id = attempt_id;
        record.phase = PublicationPhase::Writing;
        self.save_record(record)
    }

    pub fn publication_intent(&mut self) -> io::Result<ReservationRecord> {
        let mut names = self.directory.reserved.lock().unwrap();
        names.remove(&self.filename.to_lowercase());
        self.filename = self.directory.unique(&self.base, &names)?;
        names.insert(self.filename.to_lowercase());
        drop(names);

        let mut record = self
            .durable
            .clone()
            .ok_or_else(|| invalid("下载没有持久化恢复记录"))?;
        record.filename = self.filename.clone();
        record.phase = PublicationPhase::Publishing;
        self.save_record(record)
    }

    /// Leaves the journal in place until the completed task is durably committed.
    pub fn publish(&mut self) -> io::Result<()> {
        self.publish_owned()?;

        #[cfg(unix)]
        File::open(&self.directory.root)?.sync_all()?;
        Ok(())
    }

    /// Retains recognized artifacts across owner disposal; reopening must verify identity again.
    pub fn retain(mut self) {
        self.retained = true;
    }

    pub fn complete(self) -> io::Result<()> {
        self.cleanup()
    }

    /// Publishes without clobbering and reports cleanup failures; the caller owns writer durability.
    pub fn finish(mut self) -> io::Result<String> {
        let result = self.finalize();
        let cleanup = self.remove_artifacts();

        match result {
            Ok(name) => cleanup.map(|()| name),
            Err(error) => combine(Err(error), cleanup).map(|()| unreachable!()),
        }
    }

    fn finalize(&mut self) -> io::Result<String> {
        verify_identity(&self.temporary, &self.identity)?;
        let mut names = self.directory.reserved.lock().unwrap();
        names.remove(&self.filename.to_lowercase());
        loop {
            self.filename = self.directory.unique(&self.base, &names)?;
            match self.publish_owned() {
                Ok(()) => return Ok(self.filename.clone()),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
    }

    /// Both durable and ephemeral publication verify the live source immediately before
    /// the no-clobber move. A failed move must never let TempPath delete a replacement.
    fn publish_owned(&self) -> io::Result<()> {
        verify_identity(&self.temporary, &self.identity)?;
        let path = TempPath::try_from_path(&self.temporary)?;
        match path.persist_noclobber(self.directory.root.join(&self.filename)) {
            Ok(()) => Ok(()),
            Err(mut error) => {
                error.path.disable_cleanup(true);
                Err(error.error)
            }
        }
    }

    fn remove_artifacts(&self) -> io::Result<()> {
        let temporary = remove_identified_file(&self.temporary, &self.identity);

        // Remove our journal even when a replacement is preserved, so recovery cannot delete it.
        let journal = self.remove_owned_journal();

        combine(temporary, journal)
    }

    fn remove_owned_journal(&self) -> io::Result<()> {
        match std::fs::symlink_metadata(&self.journal) {
            Ok(metadata)
                if metadata.is_file()
                    && metadata.len() <= MAX_RECORD_BYTES
                    && std::fs::read(&self.journal)? == self.record_bytes =>
            {
                std::fs::remove_file(&self.journal)
            }
            Ok(_) => Err(invalid("下载记录已被替换，请检查下载目录")),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }

    /// Removes only owned artifacts and reports failures while preserving replacement files.
    pub fn cleanup(self) -> io::Result<()> {
        let result = self.remove_artifacts();
        if result.is_ok() {
            self.directory
                .reserved
                .lock()
                .unwrap()
                .remove(&self.filename.to_lowercase());
        }

        result
    }
}

impl Drop for Reservation {
    fn drop(&mut self) {
        // Explicit finish/cleanup reports errors; this is an idempotent fallback on early returns.
        if self.retained || self.durable.is_some() {
            // A durable reservation may already belong to the task index. Unwind
            // must preserve it; only explicit cleanup is allowed to delete it.
            return;
        }

        let _ = self.remove_artifacts();
        self.directory
            .reserved
            .lock()
            .unwrap()
            .remove(&self.filename.to_lowercase());
    }
}
