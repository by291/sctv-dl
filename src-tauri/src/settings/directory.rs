use std::path::{Path, PathBuf};

use tauri::Runtime;
use tauri_plugin_store::Store;

use crate::error::{AppError, ErrorCode, Result};

/// Synchronous Store policy; runtime callers use DesktopSettings's blocking boundary.
pub fn download_directory<R: Runtime>(store: &Store<R>) -> Result<Option<PathBuf>> {
    let Some(value) = store.get("downloadDirectory") else {
        return Ok(None);
    };
    let path = value
        .as_str()
        .filter(|path| !path.is_empty())
        .ok_or_else(|| AppError::new(ErrorCode::Storage, "保存的下载目录无效，请重新选择"))?;
    let path = Path::new(path).canonicalize().map_err(|error| {
        AppError::with_source(
            ErrorCode::Storage,
            "下载目录已不可用，请在设置中重新选择",
            error,
        )
    })?;
    if !path.is_dir() {
        return Err(AppError::new(
            ErrorCode::Storage,
            "下载位置不是文件夹，请重新选择",
        ));
    }

    Ok(Some(path))
}

pub fn save_download_directory<R: Runtime>(store: &Store<R>, path: &Path) -> Result<()> {
    let path = path.canonicalize().map_err(|error| {
        AppError::with_source(ErrorCode::Storage, "下载目录已不可用，请重新选择", error)
    })?;
    let text = path
        .to_str()
        .ok_or_else(|| AppError::new(ErrorCode::Storage, "无法保存此目录路径，请选择其他文件夹"))?;

    // Validate write access without acquiring the manager's long-lived directory lock.
    tempfile::Builder::new()
        .prefix(".sctv-dl-directory-check-")
        .tempfile_in(&path)
        .and_then(|file| file.close())
        .map_err(|error| {
            AppError::with_source(
                ErrorCode::Storage,
                "下载目录无法写入，请选择其他文件夹",
                error,
            )
        })?;

    super::store::save_value(
        store,
        "downloadDirectory",
        serde_json::json!(text),
        "无法保存下载目录，请检查应用数据目录",
    )
}
