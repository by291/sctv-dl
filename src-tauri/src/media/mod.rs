mod http;
pub(crate) mod policy;

pub use http::{MediaConfig, MediaServer};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Quality {
    Standard,
    Smooth,
}

impl Quality {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Standard => "standard",
            Self::Smooth => "smooth",
        }
    }
}

#[derive(Clone)]
pub struct MediaSource {
    pub quality: Quality,
    pub url: String,
}

#[derive(Serialize)]
pub struct PlaybackSource {
    pub quality: Quality,
    pub url: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaybackSession {
    pub id: String,
    pub selected_quality: Quality,
    pub sources: Vec<PlaybackSource>,
}
