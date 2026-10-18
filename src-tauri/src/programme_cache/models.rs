use chrono::{DateTime, NaiveDate};
use serde::{Deserialize, Serialize};

// Cache inputs share the normalized wire shapes; validation remains with CachePayload.
pub use crate::programmes::{
    Programme as CachedProgramme, ProgrammeContent as CachedContent, ProgrammeDate as CachedDate,
};

use crate::{
    error::{AppError, ErrorCode, Result},
    programmes::validate_id,
};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum CacheKey {
    Catalogue,
    Dates {
        #[serde(rename = "programmeId")]
        programme_id: String,
    },
    Contents {
        #[serde(rename = "programmeId")]
        programme_id: String,
        #[serde(rename = "dateId")]
        date_id: String,
    },
}

impl CacheKey {
    pub fn name(&self) -> Result<String> {
        match self {
            Self::Catalogue => Ok("catalogue".into()),
            Self::Dates { programme_id } => {
                validate_id(programme_id)?;
                Ok(format!("dates:{programme_id}"))
            }
            Self::Contents {
                programme_id,
                date_id,
            } => {
                validate_id(programme_id)?;
                validate_id(date_id)?;
                Ok(format!("contents:{programme_id}:{date_id}"))
            }
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum CachePayload {
    Catalogue {
        items: Vec<CachedProgramme>,
    },
    Dates {
        #[serde(rename = "programmeId")]
        programme_id: String,
        items: Vec<CachedDate>,
    },
    Contents {
        #[serde(rename = "programmeId")]
        programme_id: String,
        #[serde(rename = "dateId")]
        date_id: String,
        items: Vec<CachedContent>,
    },
}

impl CachePayload {
    pub fn key(&self) -> CacheKey {
        match self {
            Self::Catalogue { .. } => CacheKey::Catalogue,
            Self::Dates { programme_id, .. } => CacheKey::Dates {
                programme_id: programme_id.clone(),
            },
            Self::Contents {
                programme_id,
                date_id,
                ..
            } => CacheKey::Contents {
                programme_id: programme_id.clone(),
                date_id: date_id.clone(),
            },
        }
    }

    pub fn validate(&self) -> Result<()> {
        self.key().name()?;

        match self {
            Self::Catalogue { items } => {
                for item in items {
                    validate_id(&item.id)?;
                    valid_url(&item.cover)?;
                }
            }
            Self::Dates { items, .. } => {
                for item in items {
                    validate_id(&item.id)?;
                    valid_date(&item.date)?;
                }
            }
            Self::Contents { items, .. } => {
                for item in items {
                    validate_id(&item.id)?;
                    valid_url(&item.cover)?;
                    valid_url(&item.video)?;
                    valid_url(&item.smooth_video)?;
                }
            }
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    #[serde(flatten)]
    pub payload: CachePayload,
    pub version: u32,
    pub revision: String,
    pub fetched_at: String,
}

impl Snapshot {
    pub fn validate(&self) -> Result<()> {
        self.payload.validate()?;

        if self.version != 1 || self.revision.is_empty() {
            return Err(invalid());
        }

        valid_time(&self.fetched_at)
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BrowseState {
    pub programme_id: String,
    pub date_id: Option<String>,
    pub date: Option<String>,
    pub sort: String,
    pub scroll_y: f64,
    pub visited_at: String,
}

impl BrowseState {
    pub fn validate(&self) -> Result<()> {
        validate_id(&self.programme_id)?;

        if let Some(id) = &self.date_id {
            validate_id(id)?;
        }
        if let Some(date) = &self.date {
            valid_date(date)?;
        }

        if !matches!(self.sort.as_str(), "asc" | "desc")
            || !self.scroll_y.is_finite()
            || self.scroll_y < 0.0
        {
            return Err(invalid());
        }

        valid_time(&self.visited_at)
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct CacheRead {
    pub epoch: String,
    pub snapshot: Option<Snapshot>,
    pub persisted: bool,
    pub warning: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct CacheWriteResult {
    pub epoch: String,
    pub snapshot: Option<Snapshot>,
    pub persisted: bool,
    pub warning: Option<String>,
    pub accepted: bool,
}

#[derive(Clone, Debug, Serialize)]
pub struct BrowseRead {
    pub epoch: String,
    pub value: Option<BrowseState>,
    pub persisted: bool,
    pub warning: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct WriteResult {
    pub accepted: bool,
    pub persisted: bool,
}

#[derive(Clone, Debug, Serialize)]
pub struct ClearResult {
    pub epoch: String,
}

fn invalid() -> AppError {
    AppError::new(ErrorCode::InvalidInput, "节目缓存数据无效")
}

fn valid_url(value: &Option<String>) -> Result<()> {
    if let Some(value) = value {
        let url = reqwest::Url::parse(value).map_err(|_| invalid())?;

        if !matches!(url.scheme(), "https" | "http") {
            return Err(invalid());
        }
    }

    Ok(())
}

fn valid_date(value: &str) -> Result<()> {
    if value.len() != 10 || NaiveDate::parse_from_str(value, "%Y-%m-%d").is_err() {
        return Err(invalid());
    }

    Ok(())
}

fn valid_time(value: &str) -> Result<()> {
    if !value.ends_with('Z') || DateTime::parse_from_rfc3339(value).is_err() {
        return Err(invalid());
    }

    Ok(())
}
