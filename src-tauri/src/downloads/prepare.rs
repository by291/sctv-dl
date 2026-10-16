use reqwest::Url;
use std::collections::HashSet;

use super::{
    ContentRef, DownloadRequest, FileFailure, PreparedBatch, PreparedDownload,
    files::download_filename,
};
use crate::{
    error::{AppError, Result},
    media::{Quality, policy},
    programmes::{ProgrammeContent, ProgrammeService},
};

fn source(content: &ProgrammeContent, requested: Quality) -> Option<(Quality, &str)> {
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

pub async fn prepare_downloads(
    service: &ProgrammeService,
    request: DownloadRequest,
    origin: &Url,
) -> Result<PreparedBatch> {
    let size = serde_json::to_vec(&request)
        .map_err(|_| AppError::new("invalid-input", "下载请求无效"))?
        .len();
    if size > 16 * 1024 {
        return Err(AppError::new("invalid-input", "下载请求过大"));
    }
    for id in [&request.programme_id, &request.date_id]
        .into_iter()
        .chain(request.content_ids.iter())
    {
        crate::programmes::validate_id(id)?;
    }
    let mut seen = HashSet::new();
    let ids: Vec<_> = request
        .content_ids
        .into_iter()
        .filter(|id| seen.insert(id.clone()))
        .collect();
    if ids.is_empty() || ids.len() > 100 {
        return Err(AppError::new("invalid-input", "请选择 1 至 100 条节目内容"));
    }

    let dates = service.dates(&request.programme_id).await?;
    let date = dates
        .iter()
        .find(|date| date.id == request.date_id)
        .ok_or_else(|| AppError::new("not-found", "播出日期已不可用，请刷新后重试"))?;
    let contents = service
        .contents(&request.programme_id, &request.date_id)
        .await?;
    let mut batch = PreparedBatch::default();
    for id in ids {
        let prepared = contents
            .iter()
            .find(|content| content.id == id)
            .and_then(|content| {
                let (quality, url) = source(content, request.quality)?;
                policy::target(url, origin).ok()?;
                Some(PreparedDownload {
                    content: ContentRef {
                        programme_id: request.programme_id.clone(),
                        date_id: request.date_id.clone(),
                        content_id: id.clone(),
                    },
                    filename: download_filename(&date.date, &content.title, quality),
                    quality,
                    url: url.into(),
                })
            });
        if let Some(file) = prepared {
            batch.used_fallback |= file.quality != request.quality;
            batch.files.push(file);
        } else {
            batch.failures.push(FileFailure {
                content_id: id,
                message: "节目内容或视频已不可用，请刷新后重试".into(),
            });
        }
    }
    Ok(batch)
}
