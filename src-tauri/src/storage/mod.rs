use std::{
    fs::File,
    io::{self, Read, Write},
    path::Path,
};

use serde::{Serialize, de::DeserializeOwned};

#[derive(Debug)]
struct ReplacementSyncError(io::Error);

impl std::fmt::Display for ReplacementSyncError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "Replacement committed but directory synchronization failed: {}",
            self.0
        )
    }
}

impl std::error::Error for ReplacementSyncError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.0)
    }
}

/// True when atomic replacement succeeded but its final durability barrier failed.
/// Owners must retain the replaced document's logical state while reporting the
/// incomplete durability; treating this result as rollback can resurrect old data.
pub fn replacement_committed(error: &io::Error) -> bool {
    error
        .get_ref()
        .is_some_and(|cause| cause.is::<ReplacementSyncError>())
}

/// Reads a bounded document without modifying malformed or oversized input.
pub fn read_json<T: DeserializeOwned>(path: &Path, max_bytes: u64) -> io::Result<Option<T>> {
    let file = match File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error),
    };
    let mut bytes = Vec::new();
    file.take(max_bytes.saturating_add(1))
        .read_to_end(&mut bytes)?;
    if bytes.len() as u64 > max_bytes {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "JSON document exceeds its size limit",
        ));
    }
    serde_json::from_slice(&bytes)
        .map(Some)
        .map_err(io::Error::other)
}

/// Synchronizes a same-directory temporary file before atomically replacing the target.
/// Unix additionally synchronizes the parent directory. Windows has no portable
/// directory-sync primitive in std: file bytes and atomic replacement are guaranteed,
/// but crash durability of the directory entry remains platform dependent.
/// A post-replacement directory-sync failure is returned, although replacement has
/// already occurred; callers must not assume every error means the target is unchanged.
pub fn write_json_atomic<T: Serialize>(path: &Path, value: &T) -> io::Result<()> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    serde_json::to_writer(&mut temporary, value).map_err(io::Error::other)?;
    temporary.flush()?;
    temporary.as_file().sync_all()?;
    temporary.persist(path).map_err(|error| error.error)?;
    #[cfg(unix)]
    File::open(parent)
        .and_then(|directory| directory.sync_all())
        .map_err(|error| io::Error::new(error.kind(), ReplacementSyncError(error)))?;
    Ok(())
}
