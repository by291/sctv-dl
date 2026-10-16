use reqwest::Url;

use crate::error::{AppError, ErrorCode, Result};

pub fn default_origins() -> Vec<String> {
    ["https://fscgc.scgchc.com/", "https://fscgc.sctv-tf.com/"]
        .into_iter()
        .map(String::from)
        .collect()
}

pub fn parse_origins(raw: &[String]) -> Result<Vec<Url>> {
    raw.iter()
        .map(|origin| {
            Url::parse(origin).map_err(|error| {
                AppError::with_source(ErrorCode::InvalidInput, "视频服务地址无效", error)
            })
        })
        .collect()
}

pub fn target(raw: &str, origins: &[Url]) -> Result<Url> {
    let url = Url::parse(raw).map_err(|_| invalid())?;
    if !origins.iter().any(|origin| url.origin() == origin.origin())
        || !url.username().is_empty()
        || url.password().is_some()
        || !url.path().to_ascii_lowercase().ends_with(".mp4")
    {
        return Err(invalid());
    }

    Ok(url)
}

fn invalid() -> AppError {
    AppError::new(ErrorCode::InvalidInput, "暂不支持此视频来源")
}
