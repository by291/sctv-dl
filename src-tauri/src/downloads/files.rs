use same_file::Handle;
use serde::{Deserialize, Serialize};
use std::{
    collections::HashSet,
    fs::{File, OpenOptions},
    io::{self, Read, Seek, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};
use tempfile::TempPath;
use uuid::Uuid;

use super::filename::{MAX_STEM_UNITS, portable_stem};

pub use super::filename::download_filename;

const LOCK_MAGIC: &[u8] = b"sctv-dl download directory v1\n";
const RECOVERY_RECORD_VERSION: u8 = 1;
const MAX_RECORD_BYTES: u64 = 4096;
const MAX_PATH_UNITS: usize = 240;
const TEMPORARY_PATH_UNITS: usize = 51;
const FINAL_NAME_OVERHEAD_UNITS: usize = 16;

#[derive(Deserialize, Serialize)]
struct RecoveryRecord {
    #[serde(rename = "sctvDlDownload")]
    version: u8,
    id: String,
}

impl RecoveryRecord {
    fn new(id: Uuid) -> Self {
        Self {
            version: RECOVERY_RECORD_VERSION,
            id: id.to_string(),
        }
    }

    fn recognizes(&self, id: &str) -> bool {
        self.version == RECOVERY_RECORD_VERSION && self.id == id && Uuid::parse_str(id).is_ok()
    }
}

/// Owns a newly created artifact before the complete reservation can exist.
struct AcquiredFile {
    path: PathBuf,
    identity: Option<Handle>,
}

#[derive(Debug)]
struct UnidentifiedCreatedFile {
    path: PathBuf,
    cause: io::Error,
}

impl std::fmt::Display for UnidentifiedCreatedFile {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "无法确认新建下载文件身份，已保留该路径供检查（{}）：{}",
            self.path.display(),
            self.cause,
        )
    }
}

impl std::error::Error for UnidentifiedCreatedFile {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.cause)
    }
}

impl AcquiredFile {
    fn new(file: File, path: &Path) -> io::Result<Self> {
        // Consume the original handle: cloning must only happen after rollback owns its identity.
        let identity = Handle::from_file(file).map_err(|cause| {
            // If even metadata is unavailable, deletion cannot distinguish an external replacement.
            io::Error::new(
                cause.kind(),
                UnidentifiedCreatedFile {
                    path: path.into(),
                    cause,
                },
            )
        })?;

        Ok(Self {
            path: path.into(),
            identity: Some(identity),
        })
    }

    fn create(path: &Path) -> io::Result<Self> {
        Self::new(
            OpenOptions::new().write(true).create_new(true).open(path)?,
            path,
        )
    }

    fn into_identity(mut self) -> Handle {
        self.identity.take().unwrap()
    }

    fn into_writer(self) -> io::Result<(File, Handle)> {
        match self.identity.as_ref().unwrap().as_file().try_clone() {
            Ok(file) => Ok((file, self.into_identity())),
            Err(error) => {
                combine(Err(error), self.cleanup())?;
                unreachable!();
            }
        }
    }

    fn cleanup(mut self) -> io::Result<()> {
        let identity = self.identity.take().unwrap();
        remove_identified_file(&self.path, &identity)
    }
}

impl Drop for AcquiredFile {
    fn drop(&mut self) {
        if let Some(identity) = &self.identity {
            // Explicit acquisition failures report cleanup errors; Drop is only unwind fallback.
            let _ = remove_identified_file(&self.path, identity);
        }
    }
}

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message)
}

pub struct DownloadDirectory {
    root: PathBuf,
    _lock: Handle,
    reserved: Mutex<HashSet<String>>,
}

impl DownloadDirectory {
    /// Holds the directory's OS lock for its lifetime and recovers only recognized artifact pairs.
    pub fn open(root: &Path) -> io::Result<Arc<Self>> {
        Self::open_with(root, initialize)
    }

    fn open_with(
        root: &Path,
        initialize: impl FnOnce(&mut File, &[u8]) -> io::Result<()>,
    ) -> io::Result<Arc<Self>> {
        let root = root.canonicalize()?;
        if !root.is_dir() {
            return Err(invalid("下载位置不是文件夹"));
        }
        let lock_path = root.join(".sctv-dl.lock");
        let mut lock = match OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&lock_path)
        {
            Ok(file) => initialize_owned(file, &lock_path, LOCK_MAGIC, initialize)?,
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                if !std::fs::symlink_metadata(&lock_path)?.is_file() {
                    return Err(invalid("下载目录的应用锁无效"));
                }
                Handle::from_file(OpenOptions::new().read(true).write(true).open(&lock_path)?)?
            }
            Err(error) => return Err(error),
        };
        lock.as_file_mut().rewind()?;
        let mut magic = Vec::new();
        lock.as_file_mut().take(128).read_to_end(&mut magic)?;
        if magic != LOCK_MAGIC {
            return Err(invalid("下载目录的应用锁无效"));
        }
        lock.as_file().try_lock().map_err(|_| {
            io::Error::new(
                io::ErrorKind::WouldBlock,
                "此下载目录正由另一个桌面实例使用",
            )
        })?;
        let directory = Arc::new(Self {
            root,
            _lock: lock,
            reserved: Mutex::default(),
        });
        directory.recover()?;
        Ok(directory)
    }

    pub fn path(&self) -> &Path {
        &self.root
    }

    fn recover(&self) -> io::Result<()> {
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

    fn unique(&self, base: &str, reserved: &HashSet<String>) -> io::Result<String> {
        let occupied: HashSet<_> = std::fs::read_dir(&self.root)?
            .map(|entry| entry.map(|entry| entry.file_name().to_string_lossy().to_lowercase()))
            .collect::<io::Result<_>>()?;
        for index in 0..100_000 {
            let name = if index == 0 {
                format!("{base}.mp4")
            } else {
                format!("{base} ({index}).mp4")
            };
            let key = name.to_lowercase();
            let exists = match std::fs::symlink_metadata(self.root.join(&name)) {
                Ok(_) => true,
                Err(error) if error.kind() == io::ErrorKind::NotFound => false,
                Err(error) => return Err(error),
            };
            if !occupied.contains(&key) && !reserved.contains(&key) && !exists {
                return Ok(name);
            }
        }
        Err(invalid("下载目录内的同名文件过多"))
    }

    /// Acquires temporary artifacts and a case-insensitive final name without replacing any file.
    /// Close the returned writer before explicitly finishing or cleaning up the reservation.
    pub fn reserve(self: &Arc<Self>, filename: &str) -> io::Result<(File, Reservation)> {
        self.reserve_with(filename, initialize)
    }

    fn reserve_with(
        self: &Arc<Self>,
        filename: &str,
        initialize: impl FnOnce(&mut File, &[u8]) -> io::Result<()>,
    ) -> io::Result<(File, Reservation)> {
        let root_units = self
            .root
            .as_os_str()
            .to_string_lossy()
            .encode_utf16()
            .count();
        if root_units + TEMPORARY_PATH_UNITS > MAX_PATH_UNITS {
            return Err(invalid("下载目录路径过长，请选择较短的路径"));
        }
        let room = MAX_PATH_UNITS.saturating_sub(root_units + FINAL_NAME_OVERHEAD_UNITS);
        if room < 16 {
            return Err(invalid("下载目录路径过长，请选择较短的路径"));
        }
        let base = portable_stem(
            filename.strip_suffix(".mp4").unwrap_or(filename),
            room.min(MAX_STEM_UNITS),
        );
        let mut reserved = self.reserved.lock().unwrap();
        let filename = self.unique(&base, &reserved)?;
        let id = Uuid::new_v4();
        let temporary = self.root.join(format!(".sctv-dl-{id}.part"));
        let journal = self.root.join(format!(".sctv-dl-{id}.json"));
        let record_bytes = serde_json::to_vec(&RecoveryRecord::new(id))?;
        let record = AcquiredFile {
            path: journal.clone(),
            identity: Some(initialize_owned(
                OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(&journal)?,
                &journal,
                &record_bytes,
                initialize,
            )?),
        };
        let (file, identity) =
            match AcquiredFile::create(&temporary).and_then(AcquiredFile::into_writer) {
                Ok(owned) => owned,
                Err(error) => {
                    combine(Err(error), record.cleanup())?;
                    unreachable!();
                }
            };
        drop(record.into_identity());
        reserved.insert(filename.to_lowercase());
        Ok((
            file,
            Reservation {
                directory: self.clone(),
                base,
                filename,
                temporary,
                journal,
                identity,
                record_bytes,
            },
        ))
    }
}

pub struct Reservation {
    directory: Arc<DownloadDirectory>,
    base: String,
    filename: String,
    temporary: PathBuf,
    journal: PathBuf,
    identity: Handle,
    record_bytes: Vec<u8>,
}

impl Reservation {
    pub fn filename(&self) -> &str {
        &self.filename
    }

    pub(crate) fn writer(&self) -> io::Result<File> {
        self.identity.as_file().try_clone()
    }

    /// Publishes without clobbering and reports cleanup failures; the caller owns writer durability.
    pub fn finish(mut self) -> io::Result<String> {
        let result = self.finalize();
        let cleanup = self.remove_artifacts();
        match (result, cleanup) {
            (Ok(name), Ok(())) => Ok(name),
            (Err(error), Ok(())) | (Ok(_), Err(error)) => Err(error),
            (Err(error), Err(cleanup)) => Err(io::Error::other(format!(
                "{error}；无法清理临时文件：{cleanup}"
            ))),
        }
    }

    fn finalize(&mut self) -> io::Result<String> {
        verify_identity(&self.temporary, &self.identity)?;
        let mut names = self.directory.reserved.lock().unwrap();
        names.remove(&self.filename.to_lowercase());
        loop {
            self.filename = self.directory.unique(&self.base, &names)?;
            let path = TempPath::try_from_path(&self.temporary)?;
            match path.persist_noclobber(self.directory.root.join(&self.filename)) {
                Ok(()) => return Ok(self.filename.clone()),
                Err(mut error) => {
                    error.path.disable_cleanup(true);
                    if error.error.kind() != io::ErrorKind::AlreadyExists {
                        return Err(error.error);
                    }
                }
            }
        }
    }

    fn remove_artifacts(&self) -> io::Result<()> {
        let temporary = remove_identified_file(&self.temporary, &self.identity);
        // Remove our journal even when a replacement is preserved, so recovery cannot delete it.
        let journal = match std::fs::symlink_metadata(&self.journal) {
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
        };
        combine(temporary, journal)
    }

    /// Removes only owned artifacts and reports failures while preserving replacement files.
    pub fn cleanup(self) -> io::Result<()> {
        self.remove_artifacts()
    }
}

impl Drop for Reservation {
    fn drop(&mut self) {
        // Explicit finish/cleanup reports errors; this is an idempotent fallback on early returns.
        let _ = self.remove_artifacts();
        self.directory
            .reserved
            .lock()
            .unwrap()
            .remove(&self.filename.to_lowercase());
    }
}

fn remove_owned_file(path: &Path) -> io::Result<()> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_file() => std::fs::remove_file(path),
        Ok(_) => Err(invalid("临时下载路径已被替换，请检查下载目录")),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn initialize(file: &mut File, bytes: &[u8]) -> io::Result<()> {
    file.write_all(bytes)?;
    file.flush()
}

fn verify_identity(path: &Path, identity: &Handle) -> io::Result<()> {
    let metadata = std::fs::symlink_metadata(path)?;
    if !metadata.is_file() {
        return Err(invalid("临时下载路径已被替换，请检查下载目录"));
    }

    #[cfg(unix)]
    let matches = {
        use std::os::unix::fs::MetadataExt;
        // Metadata needs no spare descriptor, so rollback also works after handle exhaustion.
        (metadata.dev(), metadata.ino()) == (identity.dev(), identity.ino())
    };
    #[cfg(not(unix))]
    let matches = Handle::from_path(path)? == *identity;

    if !matches {
        return Err(invalid("临时下载路径已被替换，请检查下载目录"));
    }
    Ok(())
}

fn remove_identified_file(path: &Path, identity: &Handle) -> io::Result<()> {
    match verify_identity(path, identity) {
        Ok(()) => std::fs::remove_file(path),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn combine(result: io::Result<()>, cleanup: io::Result<()>) -> io::Result<()> {
    match (result, cleanup) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error),
        (Err(error), Err(cleanup)) => {
            Err(io::Error::other(format!("{error}；清理失败：{cleanup}")))
        }
    }
}

fn initialize_owned(
    file: File,
    path: &Path,
    bytes: &[u8],
    initialize: impl FnOnce(&mut File, &[u8]) -> io::Result<()>,
) -> io::Result<Handle> {
    let mut owned = AcquiredFile::new(file, path)?;
    if let Err(error) = initialize(owned.identity.as_mut().unwrap().as_file_mut(), bytes) {
        combine(Err(error), owned.cleanup())?;
        unreachable!();
    }
    Ok(owned.into_identity())
}

#[cfg(test)]
pub(super) fn hold_reservations(
    directory: &DownloadDirectory,
) -> std::sync::MutexGuard<'_, HashSet<String>> {
    directory.reserved.lock().unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn failed_write(file: &mut File, bytes: &[u8]) -> io::Result<()> {
        file.write_all(&bytes[..3])?;
        Err(io::Error::other("injected disk write failure"))
    }

    #[cfg(unix)]
    #[test]
    fn initialization_never_leaves_an_unusable_file_when_handle_cloning_is_unavailable() {
        const CHILD: &str = "SCTV_DL_ACQUISITION_TEST_CHILD";

        if std::env::var_os(CHILD).is_none() {
            let output = std::process::Command::new("/bin/sh")
                .arg("-c")
                .arg("ulimit -n 64; exec \"$1\" --exact \"$2\" --nocapture")
                .arg("download-acquisition-test")
                .arg(std::env::current_exe().unwrap())
                .arg("downloads::files::tests::initialization_never_leaves_an_unusable_file_when_handle_cloning_is_unavailable")
                .env(CHILD, "1")
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "isolated acquisition test failed:\n{}\n{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
            return;
        }

        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("newly-created.lock");
        let file = File::create(&path).unwrap();
        let mut handles = Vec::new();
        while let Ok(handle) = File::open("/dev/null") {
            handles.push(handle);
        }

        let result = initialize_owned(file, &path, LOCK_MAGIC, initialize);

        drop(handles);
        match result {
            Ok(identity) => {
                drop(identity);
                assert_eq!(std::fs::read(&path).unwrap(), LOCK_MAGIC);
            }
            Err(_) => assert!(
                !path.exists(),
                "failed acquisition left its newly created file"
            ),
        }

        let temporary = root.path().join("newly-created.part");
        let acquired = AcquiredFile::create(&temporary).unwrap();
        let mut handles = Vec::new();
        while let Ok(handle) = File::open("/dev/null") {
            handles.push(handle);
        }

        let result = acquired.into_writer();

        drop(handles);
        assert!(result.is_err());
        assert!(
            !temporary.exists(),
            "failed writer clone left its owned temporary file"
        );
    }

    #[test]
    fn removes_a_partially_written_lock_and_allows_directory_reuse() {
        let root = tempfile::tempdir().unwrap();
        assert!(DownloadDirectory::open_with(root.path(), failed_write).is_err());
        assert!(!root.path().join(".sctv-dl.lock").exists());
        assert!(DownloadDirectory::open(root.path()).is_ok());
    }

    #[cfg(unix)]
    #[test]
    fn initialization_failure_preserves_a_replacement_at_the_owned_path() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join(".sctv-dl.lock");

        let result = DownloadDirectory::open_with(root.path(), |_, _| {
            std::fs::remove_file(&path)?;
            std::fs::write(&path, b"unrelated replacement")?;
            Err(io::Error::other("injected initialization failure"))
        });

        assert!(result.is_err());
        assert_eq!(std::fs::read(path).unwrap(), b"unrelated replacement");
    }

    #[test]
    fn removes_a_partially_written_journal_and_allows_reservation_reuse() {
        let root = tempfile::tempdir().unwrap();
        let directory = DownloadDirectory::open(root.path()).unwrap();
        assert!(directory.reserve_with("clip.mp4", failed_write).is_err());
        assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 1);
        let (file, reservation) = directory.reserve("clip.mp4").unwrap();
        assert_eq!(reservation.filename(), "clip.mp4");
        drop(file);
        reservation.cleanup().unwrap();
    }
}
