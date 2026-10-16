use reqwest::Url;

use crate::error::{AppError, ErrorCode, Result};

pub fn target(raw: &str, origin: &Url) -> Result<Url> {
    let url = Url::parse(raw).map_err(|_| invalid())?;
    if url.scheme() != origin.scheme()
        || url.host_str() != origin.host_str()
        || url.port_or_known_default() != origin.port_or_known_default()
        || !url.username().is_empty()
        || url.password().is_some()
        || !url.path().to_ascii_lowercase().ends_with(".mp4")
    {
        return Err(invalid());
    }

    Ok(url)
}

fn invalid() -> AppError {
    AppError::new(ErrorCode::InvalidInput, "仅支持已验证的视频 CDN MP4 地址")
}
