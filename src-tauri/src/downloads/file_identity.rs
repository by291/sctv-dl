use std::{
    fs::{File, OpenOptions},
    io,
    path::Path,
};

use serde::{Deserialize, Serialize};

#[derive(Debug)]
pub(super) struct ReplacedFile;

impl std::fmt::Display for ReplacedFile {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("Owned file identity changed")
    }
}

impl std::error::Error for ReplacedFile {}

/// Identifies errors that establish absence or replacement of the owned file.
pub(super) fn is_missing_or_replaced(error: &io::Error) -> bool {
    error.kind() == io::ErrorKind::NotFound || is_replaced(error)
}

pub(super) fn is_replaced(error: &io::Error) -> bool {
    error
        .get_ref()
        .is_some_and(|source| source.is::<ReplacedFile>())
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum FileAccess {
    ReadOnly,
    ReadWrite,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FileIdentity {
    pub device: u64,
    pub file: u64,
}

impl FileIdentity {
    /// Reads the platform file identity from an open handle.
    pub fn read(file: &File) -> io::Result<Self> {
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;

            let metadata = file.metadata()?;
            Ok(Self {
                device: metadata.dev(),
                file: metadata.ino(),
            })
        }
        #[cfg(windows)]
        {
            use std::os::windows::io::AsRawHandle;
            use windows_sys::Win32::Storage::FileSystem::{
                BY_HANDLE_FILE_INFORMATION, GetFileInformationByHandle,
            };

            let mut information = std::mem::MaybeUninit::<BY_HANDLE_FILE_INFORMATION>::uninit();
            // SAFETY: the owned File keeps this handle valid and the API initializes
            // the output on success; no uninitialized field is read on failure.
            if unsafe { GetFileInformationByHandle(file.as_raw_handle(), information.as_mut_ptr()) }
                == 0
            {
                return Err(io::Error::last_os_error());
            }

            let information = unsafe { information.assume_init() };
            Ok(Self {
                device: u64::from(information.dwVolumeSerialNumber),
                file: u64::from(information.nFileIndexHigh) << 32
                    | u64::from(information.nFileIndexLow),
            })
        }
    }

    /// Returns a regular file handle only if it still refers to the recorded file.
    pub fn open_verified(&self, path: &Path, access: FileAccess) -> io::Result<File> {
        if !std::fs::symlink_metadata(path)?.is_file() {
            return Err(io::Error::other(ReplacedFile));
        }

        let file = OpenOptions::new()
            .read(true)
            .write(access == FileAccess::ReadWrite)
            .open(path)?;
        if !file.metadata()?.is_file() || Self::read(&file)? != *self {
            return Err(io::Error::other(ReplacedFile));
        }

        Ok(file)
    }
}
