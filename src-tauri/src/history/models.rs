pub use crate::programmes::ContentRef;

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryMetadata {
    pub content: ContentRef,
    pub programme_name: String,
    pub broadcast_date: String,
    pub title: String,
    pub cover: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistorySample {
    pub position_ms: u64,
    pub duration_ms: Option<u64>,
    pub ended: bool,
    pub sequence: u64,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEntry {
    #[serde(flatten)]
    pub metadata: HistoryMetadata,
    pub position_ms: u64,
    pub duration_ms: Option<u64>,
    pub viewed_at: String,
    pub completed: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistorySnapshot {
    pub entries: Vec<HistoryEntry>,
    pub revision: u64,
    pub persisted: bool,
    pub warning: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct HistorySession {
    pub id: String,
    pub entry: Option<HistoryEntry>,
}

#[derive(Debug, Serialize)]
pub struct RecordResult {
    pub accepted: bool,
    pub persisted: bool,
}

const MAX_SAFE_INTEGER: u64 = 9_007_199_254_740_991;

impl HistoryMetadata {
    pub fn validate(&self) -> crate::error::Result<()> {
        use crate::{
            error::{AppError, ErrorCode},
            programmes::validate_id,
        };

        validate_id(&self.content.programme_id)?;
        validate_id(&self.content.date_id)?;
        validate_id(&self.content.content_id)?;

        let date = chrono::NaiveDate::parse_from_str(&self.broadcast_date, "%Y-%m-%d");
        let valid_date = date.is_ok_and(|date| {
            date.format("%Y-%m-%d").to_string() == self.broadcast_date
                && self.broadcast_date.len() == 10
        });
        let valid_cover = self.cover.as_ref().is_none_or(|cover| {
            (cover.starts_with("http://") || cover.starts_with("https://"))
                && reqwest::Url::parse(cover).is_ok()
        });

        if !valid_date
            || !valid_cover
            || serde_json::to_vec(self).map_or(true, |bytes| bytes.len() > 16 * 1024)
        {
            return Err(AppError::new(
                ErrorCode::InvalidInput,
                "观看记录元数据无效或过大",
            ));
        }

        Ok(())
    }
}

impl HistorySample {
    pub fn validate(&self) -> crate::error::Result<()> {
        if self.sequence == 0
            || self.sequence > MAX_SAFE_INTEGER
            || self.position_ms > MAX_SAFE_INTEGER
            || self
                .duration_ms
                .is_some_and(|duration| duration > MAX_SAFE_INTEGER)
        {
            return Err(crate::error::AppError::new(
                crate::error::ErrorCode::InvalidInput,
                "观看进度无效",
            ));
        }

        Ok(())
    }

    pub fn completed(&self) -> bool {
        self.ended
            || self.duration_ms.is_some_and(|duration| {
                duration > 0 && u128::from(self.position_ms) * 100 >= u128::from(duration) * 95
            })
    }
}
