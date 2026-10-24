mod handler;
mod http;
mod local;
mod playback;
pub(crate) mod policy;
mod stream;

use serde::Serialize;

pub use crate::programmes::{MediaSource, Quality};
pub use http::{MediaConfig, MediaServer};
pub use playback::{PlaybackRequest, PlaybackService};

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
