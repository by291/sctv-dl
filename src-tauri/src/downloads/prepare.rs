use std::collections::HashSet;

use reqwest::Url;

use super::{
    ContentRef, DownloadRequest, FileFailure, PreparedBatch, PreparedDownload, download_filename,
};
use crate::{
    error::{AppError, ErrorCode, Result},
    media::policy,
    programmes::{ProgrammeService, preferred_source},
};

const MAX_REQUEST_BYTES: usize = 16 * 1024;
const MAX_REQUESTED_ITEMS: usize = 100;

/// Resolves eligible sources and reports unavailable items individually.
pub async fn prepare_downloads(
    service: &ProgrammeService,
    request: DownloadRequest,
    origins: &[Url],
) -> Result<PreparedBatch> {
    let request_bytes = serde_json::to_vec(&request)
        .map_err(|_| AppError::new(ErrorCode::InvalidInput, "下载请求无效"))?
        .len();
    if request_bytes > MAX_REQUEST_BYTES {
        return Err(AppError::new(ErrorCode::InvalidInput, "下载请求过大"));
    }

    for request_id in [&request.programme_id, &request.date_id]
        .into_iter()
        .chain(request.content_ids.iter())
    {
        crate::programmes::validate_id(request_id)?;
    }

    let mut seen = HashSet::new();
    let content_ids: Vec<_> = request
        .content_ids
        .into_iter()
        .filter(|id| seen.insert(id.clone()))
        .collect();
    if content_ids.is_empty() || content_ids.len() > MAX_REQUESTED_ITEMS {
        return Err(AppError::new(
            ErrorCode::InvalidInput,
            "请选择 1 至 100 条节目内容",
        ));
    }

    let broadcast = service
        .broadcast(&request.programme_id, &request.date_id)
        .await?;

    let programme_name = service
        .programmes()
        .await?
        .into_iter()
        .find(|programme| programme.id == request.programme_id)
        .map(|programme| programme.name)
        .unwrap_or_default();

    let mut batch = PreparedBatch::default();
    for content_id in content_ids {
        let prepared = broadcast
            .contents
            .iter()
            .find(|content| content.id == content_id)
            .and_then(|content| {
                let (quality, url) = preferred_source(content, request.quality)?;
                policy::target(url, origins).ok()?;
                let reference = ContentRef {
                    programme_id: request.programme_id.clone(),
                    date_id: request.date_id.clone(),
                    content_id: content_id.clone(),
                };

                Some(PreparedDownload {
                    metadata: crate::history::HistoryMetadata {
                        content: reference.clone(),
                        programme_name: programme_name.clone(),
                        broadcast_date: broadcast.date.date.clone(),
                        title: content.title.clone(),
                        cover: content.cover.clone(),
                    },
                    content: reference,
                    filename: download_filename(&broadcast.date.date, &content.title, quality),
                    quality,
                    url: url.into(),
                })
            });

        if let Some(file) = prepared {
            batch.used_fallback |= file.quality != request.quality;
            batch.files.push(file);
        } else {
            batch.failures.push(FileFailure {
                content_id,
                message: "节目内容或视频已不可用，请刷新后重试".into(),
            });
        }
    }

    Ok(batch)
}
