use std::{
    fs::{File, OpenOptions},
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use super::{DownloadTask, file_identity::FileIdentity, journal::ReservationRecord};
use crate::{
    error::{AppError, ErrorCode, Result},
    storage::{read_json, write_json_atomic},
};

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StoredTask {
    pub task: DownloadTask,
    pub directory: PathBuf,
    pub reservation: Option<ReservationRecord>,
    pub completed_identity: Option<FileIdentity>,
}

#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct DownloadDocument {
    pub version: u8,
    pub revision: u64,
    pub tasks: Vec<StoredTask>,
}

pub struct DownloadStore {
    path: PathBuf,
    _lock: File,
}

impl DownloadStore {
    pub fn open(path: PathBuf) -> Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(storage)?;
        }

        let lock = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(path.with_extension("lock"))
            .map_err(storage)?;
        lock.try_lock().map_err(|error| {
            AppError::with_source(
                ErrorCode::Storage,
                "下载记录正由另一实例使用，下载服务不可用",
                error,
            )
        })?;
        Ok(Self { path, _lock: lock })
    }

    pub fn load(path: &Path) -> Result<DownloadDocument> {
        let document = read_json::<DownloadDocument>(path, 32 * 1024 * 1024)
            .map_err(storage)?
            .unwrap_or(DownloadDocument {
                version: 1,
                ..Default::default()
            });
        if document.version != 1 {
            return Err(AppError::new(
                ErrorCode::Storage,
                "下载记录版本不受支持，原文件已保留",
            ));
        }

        let mut ids = std::collections::HashSet::new();
        for record in &document.tasks {
            let task = &record.task;
            if !ids.insert(&task.id)
                || uuid::Uuid::parse_str(&task.id).is_err()
                || uuid::Uuid::parse_str(&task.attempt_id).is_err()
                || !record.directory.is_absolute()
                || task.filename.contains(['/', '\\'])
                || task.filename.is_empty()
                || task.filename == "."
                || task.filename == ".."
                || task.content != task.metadata.content
            {
                return Err(AppError::new(
                    ErrorCode::Storage,
                    "下载记录损坏，原文件已保留",
                ));
            }
            task.metadata.validate().map_err(|error| {
                AppError::with_source(ErrorCode::Storage, "下载记录元数据损坏", error)
            })?;
            if let Some(reservation) = &record.reservation {
                reservation.validate().map_err(storage)?;
                if reservation.checkpoint.task_id != task.id
                    || reservation.checkpoint.attempt_id != task.attempt_id
                {
                    return Err(AppError::new(ErrorCode::Storage, "下载恢复记录不匹配"));
                }
            }
        }

        Ok(document)
    }

    pub fn save(&self, document: &DownloadDocument) -> Result<()> {
        let bytes = serde_json::to_vec(document).map_err(|error| {
            AppError::with_source(ErrorCode::Storage, "下载记录无法编码", error)
        })?;
        if bytes.len() > 32 * 1024 * 1024 {
            return Err(AppError::new(
                ErrorCode::Storage,
                "下载记录已达到存储容量，请移除不需要的已完成记录",
            ));
        }

        write_json_atomic(&self.path, document).map_err(storage)
    }
}

fn storage(error: std::io::Error) -> AppError {
    AppError::with_source(ErrorCode::Storage, "无法读写下载记录，原文件已保留", error)
}

pub(super) fn replacement_committed(error: &AppError) -> bool {
    use std::error::Error;

    error
        .source()
        .and_then(|source| source.downcast_ref::<std::io::Error>())
        .is_some_and(crate::storage::replacement_committed)
}
