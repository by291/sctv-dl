use std::path::{Path, PathBuf};

use serde_json::Value;

use super::store::SettingsStore;
use crate::error::{AppError, ErrorCode, Result};

const DOWNLOAD_DIRECTORY: &str = "downloadDirectory";

pub(super) fn download_directory(store: &SettingsStore) -> Result<Option<PathBuf>> {
    let Some(saved) = store.get(DOWNLOAD_DIRECTORY) else {
        return Ok(None);
    };

    let path = saved
        .as_str()
        .filter(|path| !path.is_empty())
        .ok_or_else(|| AppError::new(ErrorCode::Storage, "保存的下载目录无效，请重新选择"))?;
    let location = Path::new(path).canonicalize().map_err(|error| {
        AppError::with_source(
            ErrorCode::Storage,
            "下载目录已不可用，请在设置中重新选择",
            error,
        )
    })?;
    if !location.is_dir() {
        return Err(AppError::new(
            ErrorCode::Storage,
            "下载位置不是文件夹，请重新选择",
        ));
    }

    Ok(Some(location))
}

pub(super) fn save_download_directory(store: &mut SettingsStore, path: &Path) -> Result<()> {
    let location = path.canonicalize().map_err(|error| {
        AppError::with_source(ErrorCode::Storage, "下载目录已不可用，请重新选择", error)
    })?;
    let text = location
        .to_str()
        .ok_or_else(|| AppError::new(ErrorCode::Storage, "无法保存此目录路径，请选择其他文件夹"))?;

    // Validate write access without acquiring the manager's long-lived directory lock.
    tempfile::Builder::new()
        .prefix(".sctv-dl-directory-check-")
        .tempfile_in(&location)
        .and_then(|file| file.close())
        .map_err(|error| {
            AppError::with_source(
                ErrorCode::Storage,
                "下载目录无法写入，请选择其他文件夹",
                error,
            )
        })?;

    store.save_value(
        DOWNLOAD_DIRECTORY,
        Value::String(text.to_owned()),
        "无法保存下载目录，请检查应用数据目录",
    )
}
