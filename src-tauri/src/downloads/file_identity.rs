use std::{
    fs::{File, OpenOptions},
    io,
    path::Path,
};

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FileIdentity {
    pub device: u64,
    pub file: u64,
}

impl FileIdentity {
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

    pub fn open_verified(&self, path: &Path, write: bool) -> io::Result<File> {
        if !std::fs::symlink_metadata(path)?.is_file() {
            return Err(io::Error::other(
                "Owned file was replaced by a non-regular path",
            ));
        }

        let file = OpenOptions::new().read(true).write(write).open(path)?;
        if !file.metadata()?.is_file() || Self::read(&file)? != *self {
            return Err(io::Error::other("Owned file identity changed"));
        }

        Ok(file)
    }
}
