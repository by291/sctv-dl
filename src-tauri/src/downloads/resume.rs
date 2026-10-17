use super::journal::ResumeCheckpoint;
use reqwest::{StatusCode, header::HeaderMap};

#[derive(Debug, PartialEq, Eq)]
pub enum ResumeDecision {
    Append {
        offset: u64,
        total: u64,
        etag: String,
    },
    AlreadyComplete,
    RestartRequired {
        reason: String,
    },
}

pub fn strong_etag(value: &str) -> bool {
    value.len() >= 2
        && value.starts_with('"')
        && value.ends_with('"')
        && value[1..value.len() - 1]
            .bytes()
            .all(|byte| byte >= 0x21 && byte != b'"' && byte != 0x7f)
}

pub fn decide(
    checkpoint: &ResumeCheckpoint,
    status: StatusCode,
    headers: &HeaderMap,
    actual_length: u64,
) -> ResumeDecision {
    let restart = || ResumeDecision::RestartRequired {
        reason: "视频来源已改变或不支持安全续传，请重新下载".into(),
    };
    let (Some(total), Some(etag)) = (
        checkpoint.total_bytes,
        checkpoint.etag.as_ref().filter(|etag| strong_etag(etag)),
    ) else {
        return restart();
    };
    if headers.get("etag").and_then(|value| value.to_str().ok()) != Some(etag.as_str())
        || actual_length != checkpoint.committed_bytes
    {
        return restart();
    }
    let range = headers
        .get("content-range")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("");
    if status == StatusCode::RANGE_NOT_SATISFIABLE
        && checkpoint.committed_bytes == total
        && range == format!("bytes */{total}")
    {
        return ResumeDecision::AlreadyComplete;
    }
    if status != StatusCode::PARTIAL_CONTENT {
        return restart();
    }
    let Some((bounds, returned_total)) = range
        .strip_prefix("bytes ")
        .and_then(|value| value.split_once('/'))
    else {
        return restart();
    };
    let Some((start, end)) = bounds.split_once('-') else {
        return restart();
    };
    let numbers = (
        start.parse::<u64>(),
        end.parse::<u64>(),
        returned_total.parse::<u64>(),
    );
    let (Ok(start), Ok(end), Ok(returned_total)) = numbers else {
        return restart();
    };
    if start != checkpoint.committed_bytes
        || returned_total != total
        || end.checked_add(1) != Some(total)
        || start > end
    {
        return restart();
    }
    if headers.get("content-length").is_some_and(|value| {
        value
            .to_str()
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            != Some(end - start + 1)
    }) {
        return restart();
    }
    ResumeDecision::Append {
        offset: start,
        total,
        etag: etag.clone(),
    }
}
