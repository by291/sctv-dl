use reqwest::Url;
use std::collections::HashSet;

use super::{
    ContentRef, DownloadRequest, FileFailure, PreparedBatch, PreparedDownload, download_filename,
};
use crate::{
    error::{AppError, ErrorCode, Result},
    media::policy,
    programmes::{ProgrammeService, preferred_source},
};

pub async fn prepare_downloads(
    service: &ProgrammeService,
    request: DownloadRequest,
    origins: &[Url],
) -> Result<PreparedBatch> {
    let size = serde_json::to_vec(&request)
        .map_err(|_| AppError::new(ErrorCode::InvalidInput, "下载请求无效"))?
        .len();
    if size > 16 * 1024 {
        return Err(AppError::new(ErrorCode::InvalidInput, "下载请求过大"));
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
    for id in ids {
        let prepared = broadcast
            .contents
            .iter()
            .find(|content| content.id == id)
            .and_then(|content| {
                let (quality, url) = preferred_source(content, request.quality)?;
                policy::target(url, origins).ok()?;
                Some(PreparedDownload {
                    metadata: crate::history::HistoryMetadata {
                        content: ContentRef {
                            programme_id: request.programme_id.clone(),
                            date_id: request.date_id.clone(),
                            content_id: id.clone(),
                        },
                        programme_name: programme_name.clone(),
                        broadcast_date: broadcast.date.date.clone(),
                        title: content.title.clone(),
                        cover: content.cover.clone(),
                    },
                    content: ContentRef {
                        programme_id: request.programme_id.clone(),
                        date_id: request.date_id.clone(),
                        content_id: id.clone(),
                    },
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
                content_id: id,
                message: "节目内容或视频已不可用，请刷新后重试".into(),
            });
        }
    }

    Ok(batch)
}
