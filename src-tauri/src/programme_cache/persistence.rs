use std::{
    fs::{File, OpenOptions},
    io,
    path::{Path, PathBuf},
};

use serde::de::DeserializeOwned;
use uuid::Uuid;

use crate::storage::{read_json, replacement_committed, write_json_atomic};

use super::{MAX_BYTES, manifest::Manifest, models::Snapshot};

pub(super) enum DiskRead<T> {
    Missing,
    Found(T),
    Corrupt(io::Error),
    Unavailable(io::Error),
}

pub(super) enum CommitOutcome {
    Durable,
    Replaced(io::Error),
    Unchanged(io::Error),
}

impl CommitOutcome {
    pub(super) fn applied(&self) -> bool {
        matches!(self, Self::Durable | Self::Replaced(_))
    }
}

/// The process lock and cache paths remain owned through each blocking worker.
/// Snapshot files are published before their index; cleanup only follows index
/// replacement, including replacement whose directory sync reports failure.
pub(super) struct CacheStorage {
    root: PathBuf,
    _lock: Option<File>,
    writable: bool,
}

impl CacheStorage {
    pub(super) fn open(root: PathBuf) -> (Self, io::Result<()>) {
        let lock = (|| {
            std::fs::create_dir_all(&root)?;

            let file = OpenOptions::new()
                .read(true)
                .write(true)
                .create(true)
                .truncate(false)
                .open(root.join("cache.lock"))?;
            file.try_lock()?;

            Ok::<_, io::Error>(file)
        })();

        match lock {
            Ok(lock) => (
                Self {
                    root,
                    _lock: Some(lock),
                    writable: true,
                },
                Ok(()),
            ),
            Err(error) => (
                Self {
                    root,
                    _lock: None,
                    writable: false,
                },
                Err(error),
            ),
        }
    }

    pub(super) fn unavailable() -> Self {
        Self {
            root: PathBuf::new(),
            _lock: None,
            writable: false,
        }
    }

    pub(super) fn writable(&self) -> bool {
        self.writable
    }

    pub(super) fn protect_unreadable_manifest(&mut self) {
        // The unknown index may still reference valid snapshots. Keep the lock
        // for this owner, but preserve the file until a fresh owner can read it.
        self.writable = false;
    }

    pub(super) fn read_manifest(&self) -> DiskRead<Manifest> {
        read_validated(
            &self.root.join("manifest.json"),
            1024 * 1024,
            Manifest::valid,
        )
    }

    pub(super) fn read_snapshot(&self, manifest: &Manifest, key: &str) -> DiskRead<Snapshot> {
        let Some(entry) = manifest.entries.get(key) else {
            return DiskRead::Missing;
        };

        read_validated(
            &self.root.join(&manifest.epoch).join(&entry.file),
            MAX_BYTES as u64,
            |snapshot: &Snapshot| {
                snapshot.validate().is_ok()
                    && snapshot.payload.key().name().is_ok_and(|name| name == key)
            },
        )
    }

    pub(super) fn commit_manifest(&self, manifest: &Manifest) -> CommitOutcome {
        match write_json_atomic(&self.root.join("manifest.json"), manifest) {
            Ok(()) => CommitOutcome::Durable,
            Err(error) if replacement_committed(&error) => CommitOutcome::Replaced(error),
            Err(error) => CommitOutcome::Unchanged(error),
        }
    }

    pub(super) fn commit_snapshot(
        &self,
        manifest: &Manifest,
        key: &str,
        snapshot: &Snapshot,
    ) -> CommitOutcome {
        let directory = self.root.join(&manifest.epoch);
        let entry = &manifest.entries[key];
        let snapshot_write = std::fs::create_dir_all(&directory)
            .and_then(|()| write_json_atomic(&directory.join(&entry.file), snapshot));

        if let Err(error) = snapshot_write {
            // A snapshot replacement alone never commits its manifest entry.
            return CommitOutcome::Unchanged(error);
        }

        self.commit_manifest(manifest)
    }

    pub(super) fn cleanup_entries(&self, old: &Manifest, next: &Manifest) {
        for entry in old.entries.values() {
            if !next.entries.values().any(|value| value.file == entry.file) {
                // The index is already replaced. Unreferenced files are harmless
                // debris; a later clear retries this best-effort cleanup.
                let _ = std::fs::remove_file(self.root.join(&old.epoch).join(&entry.file));
            }
        }
    }

    pub(super) fn cleanup_epochs(&self, current_epoch: &str) -> io::Result<()> {
        for entry in std::fs::read_dir(&self.root)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().into_owned();

            if name != current_epoch
                && Uuid::parse_str(&name).is_ok()
                && entry.file_type()?.is_dir()
            {
                std::fs::remove_dir_all(entry.path())?;
            }
        }

        Ok(())
    }
}

fn read_validated<T: DeserializeOwned>(
    path: &Path,
    max_bytes: u64,
    valid: impl FnOnce(&T) -> bool,
) -> DiskRead<T> {
    match read_json(path, max_bytes) {
        Ok(None) => DiskRead::Missing,
        Ok(Some(value)) if valid(&value) => DiskRead::Found(value),
        Ok(Some(_)) => DiskRead::Corrupt(io::Error::new(
            io::ErrorKind::InvalidData,
            "Invalid programme cache document",
        )),
        Err(error)
            if error.kind() == io::ErrorKind::InvalidData
                || error
                    .get_ref()
                    .is_some_and(|cause| cause.is::<serde_json::Error>()) =>
        {
            DiskRead::Corrupt(error)
        }
        Err(error) => DiskRead::Unavailable(error),
    }
}
