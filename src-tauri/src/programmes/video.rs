use serde::{Deserialize, Serialize};

use super::ProgrammeContent;

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

pub(crate) struct PlaybackSelection {
    pub selected_quality: Quality,
    pub sources: Vec<MediaSource>,
}

pub(crate) fn playback_selection(
    content: &ProgrammeContent,
    requested: Quality,
) -> Option<PlaybackSelection> {
    let mut sources = Vec::new();
    if let Some(url) = &content.video {
        sources.push(MediaSource {
            quality: Quality::Standard,
            url: url.clone(),
        });
    }
    if let Some(url) = &content.smooth_video
        && !sources.iter().any(|source| &source.url == url)
    {
        sources.push(MediaSource {
            quality: Quality::Smooth,
            url: url.clone(),
        });
    }

    // Playback offers distinct URLs. A duplicate smooth URL retains the standard label.
    let selected_quality = sources
        .iter()
        .find(|source| source.quality == requested)
        .or_else(|| sources.first())?
        .quality;

    Some(PlaybackSelection {
        selected_quality,
        sources,
    })
}

pub(crate) fn preferred_source(
    content: &ProgrammeContent,
    requested: Quality,
) -> Option<(Quality, &str)> {
    // Downloads retain the requested quality even when both fields reference the same URL.
    match (
        requested,
        content.video.as_deref(),
        content.smooth_video.as_deref(),
    ) {
        (Quality::Smooth, _, Some(url)) => Some((Quality::Smooth, url)),
        (_, Some(url), _) => Some((Quality::Standard, url)),
        (_, _, Some(url)) => Some((Quality::Smooth, url)),
        _ => None,
    }
}
