use crate::media::Quality;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContentRef {
    pub programme_id: String,
    pub date_id: String,
    pub content_id: String,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DownloadRequest {
    pub programme_id: String,
    pub date_id: String,
    pub content_ids: Vec<String>,
    pub quality: Quality,
}

pub struct PreparedDownload {
    pub content: ContentRef,
    pub filename: String,
    pub quality: Quality,
    pub url: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum TaskState {
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled,
}

impl TaskState {
    pub fn is_terminal(self) -> bool {
        matches!(self, Self::Completed | Self::Failed | Self::Cancelled)
    }
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadTask {
    pub id: String,
    pub content: ContentRef,
    pub filename: String,
    pub quality: Quality,
    pub state: TaskState,
    pub received_bytes: u64,
    pub total_bytes: Option<u64>,
    pub error: Option<String>,
    pub revision: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileFailure {
    pub content_id: String,
    pub message: String,
}

#[derive(Default)]
pub struct PreparedBatch {
    pub files: Vec<PreparedDownload>,
    pub failures: Vec<FileFailure>,
    pub used_fallback: bool,
}

#[derive(Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadStart {
    pub task_ids: Vec<String>,
    pub failures: Vec<FileFailure>,
    pub used_fallback: bool,
}
