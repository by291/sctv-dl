mod artifacts;
mod recovery;
mod reservation;

use std::{
    collections::HashSet,
    fs::{File, OpenOptions},
    io::{self, Read, Seek},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

use same_file::Handle;
use uuid::Uuid;

pub use super::filename::download_filename;
use super::filename::{MAX_STEM_UNITS, portable_stem};
use artifacts::{AcquiredFile, combine, initialize, initialize_owned, invalid};
use recovery::RecoveryRecord;
pub use reservation::Reservation;

const LOCK_MAGIC: &[u8] = b"sctv-dl download directory v1\n";
const MAX_RECORD_BYTES: u64 = 4096;
const MAX_PATH_UNITS: usize = 240;
const TEMPORARY_PATH_UNITS: usize = 51;
const FINAL_NAME_OVERHEAD_UNITS: usize = 16;

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
                durable: None,
                retained: false,
            },
        ))
    }
}

#[cfg(test)]
pub(super) fn hold_reservations(
    directory: &DownloadDirectory,
) -> std::sync::MutexGuard<'_, HashSet<String>> {
    directory.reserved.lock().unwrap()
}

#[cfg(test)]
mod tests {
    use std::io::Write;

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

#[cfg(test)]
type RecordWriteHook = Box<dyn FnOnce(&Path)>;

#[cfg(test)]
thread_local! {
    pub(super) static RECORD_WRITE_HOOK: std::cell::RefCell<Option<RecordWriteHook>> = Default::default();
}
