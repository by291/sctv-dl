use std::{
    fs::{File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
};

use same_file::Handle;

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
        Ok(_) => Err(invalid("临时下载路径已被替换，请检查下载目录")),
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

pub(super) fn remove_identified_file(path: &Path, identity: &Handle) -> io::Result<()> {
    match verify_identity(path, identity) {
        Ok(()) => std::fs::remove_file(path),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
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
