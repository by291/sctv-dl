use same_file::Handle;
use std::{
    collections::HashSet,
    fs::{File, OpenOptions},
    io::{self, Read, Seek, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};
use tempfile::TempPath;
use uuid::Uuid;

use crate::media::Quality;

const LOCK_MAGIC: &[u8] = b"sctv-dl download directory v1\n";

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message)
}

fn stem(value: &str, units: usize) -> String {
    let mut result = String::new();
    let mut used = 0;
    for character in value.chars() {
        let character = if character.is_control() || "<>:\"/\\|?*".contains(character) {
            '_'
        } else {
            character
        };
        if used + character.len_utf16() > units || result.len() + character.len_utf8() > 220 {
            break;
        }
        used += character.len_utf16();
        result.push(character);
    }
    let mut result = result.trim_end_matches(['.', ' ']).to_owned();
    if result.is_empty() {
        result.push_str("video");
    }
    let device = result
        .split('.')
        .next()
        .unwrap()
        .trim_end()
        .to_ascii_uppercase();
    if ["CON", "PRN", "AUX", "NUL"].contains(&device.as_str())
        || device
            .strip_prefix("COM")
            .or_else(|| device.strip_prefix("LPT"))
            .is_some_and(|suffix| {
                ["1", "2", "3", "4", "5", "6", "7", "8", "9", "¹", "²", "³"].contains(&suffix)
            })
    {
        result.insert(0, '_');
    }
    result
}

pub fn download_filename(date: &str, title: &str, quality: Quality) -> String {
    let quality = if quality == Quality::Standard {
        "标准"
    } else {
        "流畅"
    };
    format!("{}.mp4", stem(&format!("{date}_{title}_{quality}"), 150))
}

pub struct DownloadDirectory {
    root: PathBuf,
    _lock: File,
    reserved: Mutex<HashSet<String>>,
}

impl DownloadDirectory {
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
                OpenOptions::new().read(true).write(true).open(&lock_path)?
            }
            Err(error) => return Err(error),
        };
        lock.rewind()?;
        let mut magic = Vec::new();
        (&mut lock).take(128).read_to_end(&mut magic)?;
        if magic != LOCK_MAGIC {
            return Err(invalid("下载目录的应用锁无效"));
        }
        lock.try_lock().map_err(|_| {
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
            if !entry.file_type()?.is_file() || entry.metadata()?.len() > 4096 {
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
            if Uuid::parse_str(id).is_err() {
                continue;
            }
            let Ok(value) =
                serde_json::from_slice::<serde_json::Value>(&std::fs::read(entry.path())?)
            else {
                continue;
            };
            if value["sctvDlDownload"] != 1 || value["id"] != id {
                continue;
            }
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

    pub fn reserve(self: &Arc<Self>, filename: &str) -> io::Result<(File, Reservation)> {
        self.reserve_with(filename, initialize)
    }

    fn reserve_with(
        self: &Arc<Self>,
        filename: &str,
        initialize: impl FnOnce(&mut File, &[u8]) -> io::Result<()>,
    ) -> io::Result<(File, Reservation)> {
        if self
            .root
            .as_os_str()
            .to_string_lossy()
            .encode_utf16()
            .count()
            + 51
            > 240
        {
            return Err(invalid("下载目录路径过长，请选择较短的路径"));
        }
        let room = 240_usize.saturating_sub(
            self.root
                .as_os_str()
                .to_string_lossy()
                .encode_utf16()
                .count()
                + 16,
        );
        if room < 16 {
            return Err(invalid("下载目录路径过长，请选择较短的路径"));
        }
        let base = stem(
            filename.strip_suffix(".mp4").unwrap_or(filename),
            room.min(150),
        );
        let mut reserved = self.reserved.lock().unwrap();
        let filename = self.unique(&base, &reserved)?;
        let id = Uuid::new_v4();
        let temporary = self.root.join(format!(".sctv-dl-{id}.part"));
        let journal = self.root.join(format!(".sctv-dl-{id}.json"));
        let record = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&journal)?;
        let record_bytes =
            serde_json::to_vec(&serde_json::json!({"sctvDlDownload":1,"id":id.to_string()}))?;
        drop(initialize_owned(
            record,
            &journal,
            &record_bytes,
            initialize,
        )?);
        let file = match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)
        {
            Ok(file) => file,
            Err(error) => {
                std::fs::remove_file(&journal)?;
                return Err(error);
            }
        };
        let identity = Handle::from_file(file.try_clone()?)?;
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
                    && metadata.len() <= 4096
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

    pub fn cleanup(self) -> io::Result<()> {
        self.remove_artifacts()
    }
}

impl Drop for Reservation {
    fn drop(&mut self) {
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
    if !std::fs::symlink_metadata(path)?.is_file() || Handle::from_path(path)? != *identity {
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
    mut file: File,
    path: &Path,
    bytes: &[u8],
    initialize: impl FnOnce(&mut File, &[u8]) -> io::Result<()>,
) -> io::Result<File> {
    let identity = Handle::from_file(file.try_clone()?)?;
    if let Err(error) = initialize(&mut file, bytes) {
        drop(file);
        combine(Err(error), remove_identified_file(path, &identity))?;
        unreachable!();
    }
    Ok(file)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn failed_write(file: &mut File, bytes: &[u8]) -> io::Result<()> {
        file.write_all(&bytes[..3])?;
        Err(io::Error::other("injected disk write failure"))
    }

    #[test]
    fn removes_a_partially_written_lock_and_allows_directory_reuse() {
        let root = tempfile::tempdir().unwrap();
        assert!(DownloadDirectory::open_with(root.path(), failed_write).is_err());
        assert!(!root.path().join(".sctv-dl.lock").exists());
        assert!(DownloadDirectory::open(root.path()).is_ok());
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
