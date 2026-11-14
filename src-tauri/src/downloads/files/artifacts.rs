use std::{
    fs::{File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
};

use same_file::Handle;

use crate::downloads::file_identity::ReplacedFile;

/// Owns a newly created artifact before the complete reservation can exist.
pub(super) struct AcquiredFile {
    pub(super) path: PathBuf,
    pub(super) identity: Option<Handle>,
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
            "Could not verify newly created download file at {}; preserved for inspection: {}",
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
    pub(super) fn new(file: File, path: &Path) -> io::Result<Self> {
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

    pub(super) fn create(path: &Path) -> io::Result<Self> {
        Self::new(
            OpenOptions::new().write(true).create_new(true).open(path)?,
            path,
        )
    }

    pub(super) fn into_identity(mut self) -> Handle {
        self.identity.take().unwrap()
    }

    pub(super) fn into_writer(self) -> io::Result<(File, Handle)> {
        match self.identity.as_ref().unwrap().as_file().try_clone() {
            Ok(file) => Ok((file, self.into_identity())),
            Err(error) => {
                combine(Err(error), self.cleanup())?;
                unreachable!();
            }
        }
    }

    pub(super) fn cleanup(mut self) -> io::Result<()> {
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

pub(super) fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message)
}

pub(super) fn remove_owned_file(path: &Path) -> io::Result<()> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_file() => std::fs::remove_file(path),
        Ok(_) => Err(invalid("Temporary download path was replaced")),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

pub(super) fn initialize(file: &mut File, bytes: &[u8]) -> io::Result<()> {
    file.write_all(bytes)?;
    file.flush()
}

pub(super) fn verify_identity(path: &Path, identity: &Handle) -> io::Result<()> {
    let metadata = std::fs::symlink_metadata(path)?;
    if !metadata.is_file() {
        return Err(io::Error::other(ReplacedFile));
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
        return Err(io::Error::other(ReplacedFile));
    }

    Ok(())
}

/// Removes an owned file without trusting the final entry at its public path.
pub(super) fn remove_identified_file(path: &Path, identity: &Handle) -> io::Result<()> {
    match remove_verified_file(path, |candidate| verify_identity(candidate, identity)) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        result => result,
    }
}

/// Moves the directory entry into an app-created directory before verifying and unlinking it.
pub(in crate::downloads) fn remove_verified_file(
    path: &Path,
    verify: impl Fn(&Path) -> io::Result<()>,
) -> io::Result<()> {
    verify(path)?;
    let parent = path
        .parent()
        .ok_or_else(|| invalid("Owned file has no parent"))?;
    let quarantine = create_quarantine(parent)?;
    let moved = quarantine.join("file");

    // Preserve the moved entry across interruption and restore errors. Empty directories are
    // removed explicitly, so cleanup never recursively deletes an unverified entry.
    let result = move_and_remove(path, &moved, verify);
    let _ = std::fs::remove_dir(quarantine);
    result
}

fn create_quarantine(parent: &Path) -> io::Result<PathBuf> {
    let mut builder = tempfile::Builder::new();
    builder.prefix(".sctv-delete-");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        const OWNER_DIRECTORY_MODE: u32 = 0o700;
        builder.permissions(std::fs::Permissions::from_mode(OWNER_DIRECTORY_MODE));
    }

    Ok(builder.tempdir_in(parent)?.keep())
}

fn move_and_remove(
    path: &Path,
    moved: &Path,
    verify: impl Fn(&Path) -> io::Result<()>,
) -> io::Result<()> {
    rename_without_replacing(path, moved)?;
    let removed = verify(moved).and_then(|()| std::fs::remove_file(moved));

    match removed {
        Ok(()) => Ok(()),
        Err(error) => {
            let restored = rename_without_replacing(moved, path).map_err(|restore| {
                io::Error::new(
                    restore.kind(),
                    format!(
                        "Cannot restore {} from {}: {restore}",
                        path.display(),
                        moved.display(),
                    ),
                )
            });
            combine(Err(error), restored)
        }
    }
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
fn rename_without_replacing(source: &Path, destination: &Path) -> io::Result<()> {
    use rustix::fs::{CWD, RenameFlags, renameat_with};

    renameat_with(CWD, source, CWD, destination, RenameFlags::NOREPLACE)?;
    Ok(())
}

#[cfg(windows)]
fn rename_without_replacing(source: &Path, destination: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::MoveFileExW;

    let source: Vec<_> = source.as_os_str().encode_wide().chain([0]).collect();
    let destination: Vec<_> = destination.as_os_str().encode_wide().chain([0]).collect();

    // SAFETY: Both path buffers are null-terminated and live through the synchronous call.
    // Omitting MOVEFILE_REPLACE_EXISTING ensures an occupied destination is preserved.
    if unsafe { MoveFileExW(source.as_ptr(), destination.as_ptr(), 0) } == 0 {
        return Err(io::Error::last_os_error());
    }

    Ok(())
}

pub(super) fn combine(result: io::Result<()>, cleanup: io::Result<()>) -> io::Result<()> {
    match (result, cleanup) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error),
        (Err(error), Err(cleanup)) => Err(io::Error::other(CleanupFailure {
            primary: error,
            cleanup,
        })),
    }
}

pub(super) fn initialize_owned(
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
mod tests {
    use std::{cell::Cell, fs};

    use super::*;

    #[test]
    fn preserves_a_file_created_after_the_original_identity_check() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("clip.mp4");
        fs::write(&path, b"original").unwrap();
        let identity = Handle::from_path(&path).unwrap();
        let first_check = Cell::new(true);

        let removed = remove_verified_file(&path, |candidate| {
            verify_identity(candidate, &identity)?;
            if first_check.replace(false) {
                fs::rename(&path, directory.path().join("original.mp4"))?;
                fs::write(&path, b"replacement")?;
            }

            Ok(())
        });

        assert!(removed.is_err());
        assert_eq!(fs::read(&path).unwrap(), b"replacement");
        assert_eq!(
            fs::read(directory.path().join("original.mp4")).unwrap(),
            b"original"
        );
    }

    #[test]
    fn keeps_both_replacements_when_the_original_path_is_occupied_during_restore() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("clip.mp4");
        fs::write(&path, b"original").unwrap();
        let identity = Handle::from_path(&path).unwrap();
        let quarantined_path = std::cell::RefCell::new(None);

        let removed = remove_verified_file(&path, |candidate| {
            if candidate == path {
                verify_identity(candidate, &identity)?;
                fs::rename(&path, directory.path().join("original.mp4"))?;
                fs::write(&path, b"first replacement")?;
            } else {
                fs::write(&path, b"second replacement")?;
                quarantined_path.replace(Some(candidate.to_owned()));
                verify_identity(candidate, &identity)?;
            }

            Ok(())
        });

        assert!(removed.is_err());
        assert_eq!(fs::read(&path).unwrap(), b"second replacement");
        assert_eq!(
            fs::read(quarantined_path.into_inner().unwrap()).unwrap(),
            b"first replacement"
        );
    }
}

#[derive(Debug)]
struct CleanupFailure {
    primary: io::Error,
    cleanup: io::Error,
}

impl std::fmt::Display for CleanupFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "primary: {}; cleanup: {}",
            self.primary, self.cleanup
        )
    }
}

impl std::error::Error for CleanupFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.primary)
    }
}
