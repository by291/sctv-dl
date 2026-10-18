use serde::{Deserialize, Serialize};

use super::file_identity::FileIdentity;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ResumeCheckpoint {
    pub task_id: String,
    pub attempt_id: String,
    pub file_identity: FileIdentity,
    pub committed_bytes: u64,
    pub total_bytes: Option<u64>,
    pub etag: Option<String>,
}

impl ResumeCheckpoint {
    pub fn resumable(&self) -> bool {
        self.total_bytes
            .is_some_and(|total| self.committed_bytes <= total)
            && self.etag.as_deref().is_some_and(super::resume::strong_etag)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum PublicationPhase {
    Writing,
    Publishing,
    Published,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReservationRecord {
    pub sctv_dl_download: u8,
    pub id: String,
    pub filename: String,
    pub checkpoint: ResumeCheckpoint,
    pub phase: PublicationPhase,
}

impl ReservationRecord {
    pub fn validate(&self) -> std::io::Result<()> {
        if self.sctv_dl_download != 2
            || uuid::Uuid::parse_str(&self.id).is_err()
            || self.filename.is_empty()
            || self.filename.contains(['/', '\\'])
            || self.filename == "."
            || self.filename == ".."
            || self.checkpoint.task_id.is_empty()
            || self.checkpoint.attempt_id.is_empty()
            || self
                .checkpoint
                .total_bytes
                .is_some_and(|total| self.checkpoint.committed_bytes > total)
        {
            return Err(std::io::Error::other("Invalid download recovery record"));
        }

        Ok(())
    }
}
