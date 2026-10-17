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

#[derive(Clone)]
pub struct PreparedDownload {
    pub metadata: crate::history::HistoryMetadata,
    pub content: ContentRef,
    pub filename: String,
    pub quality: Quality,
    pub url: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum TaskState {
    Queued,
    Running,
    Pausing,
    Paused,
    Interrupted,
    Finalizing,
    Missing,
    Completed,
    Failed,
    Cancelled,
}

impl TaskState {
    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            Self::Completed
                | Self::Failed
                | Self::Cancelled
                | Self::Missing
                | Self::Paused
                | Self::Interrupted
        )
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadTask {
    pub attempt_id: String,
    pub created_at: String,
    pub metadata: crate::history::HistoryMetadata,
    pub can_resume: bool,
    pub file_available: bool,
    pub has_partial: bool,
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

impl DownloadTask {
    pub fn unfinished(&self) -> bool {
        matches!(
            self.state,
            TaskState::Queued
                | TaskState::Running
                | TaskState::Pausing
                | TaskState::Paused
                | TaskState::Interrupted
                | TaskState::Finalizing
        ) || self.state == TaskState::Failed && self.has_partial
    }
    pub fn active(&self) -> bool {
        matches!(
            self.state,
            TaskState::Queued | TaskState::Running | TaskState::Pausing | TaskState::Finalizing
        )
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct DownloadSnapshot {
    pub epoch: String,
    pub revision: u64,
    pub tasks: Vec<DownloadTask>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum DownloadEvent {
    Upsert {
        epoch: String,
        revision: u64,
        task: Box<DownloadTask>,
    },
    Remove {
        epoch: String,
        revision: u64,
        #[serde(rename = "taskId")]
        task_id: String,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum DownloadAction {
    Pause,
    Resume,
    Restart,
    Cancel,
    Remove,
    DeleteFile,
    OpenFile,
    RevealFile,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DownloadActionRequest {
    pub task_id: String,
    pub attempt_id: String,
    pub action: DownloadAction,
}

#[derive(Debug, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum DownloadActionResult {
    Applied { task: Option<Box<DownloadTask>> },
    Skipped { message: String },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StopIntent {
    Pause,
    Cancel,
    Exit,
}
