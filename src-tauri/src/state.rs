use crate::{error::Result, programmes::ProgrammeService, requests::RequestRegistry};
use std::sync::Arc;

pub struct AppState {
    pub programmes: Result<ProgrammeService>,
    pub requests: Arc<RequestRegistry>,
}
impl AppState {
    pub fn new(programmes: Result<ProgrammeService>) -> Self {
        Self {
            programmes,
            requests: Arc::default(),
        }
    }
}

pub struct PlaybackState(pub Result<crate::media::PlaybackService>);
