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

// The historical CDN rejects requests without a User-Agent, including HEAD probes.
pub(crate) const USER_AGENT: &str = concat!("sctv-dl/", env!("CARGO_PKG_VERSION"));

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
