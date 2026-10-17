use crate::{
    downloads::{DownloadAction, DownloadActionRequest, DownloadActionResult, DownloadManager},
    error::{AppError, ErrorCode, Result},
    lifecycle::OperationGuard,
    media::PlaybackService,
};
use std::sync::Arc;
use tauri::{AppHandle, Runtime};
use tauri_plugin_opener::OpenerExt;

pub async fn act_on_file<R: Runtime>(
    app: AppHandle<R>,
    downloads: &DownloadManager,
    playback: Option<PlaybackService>,
    request: DownloadActionRequest,
    operation: Arc<OperationGuard>,
) -> Result<DownloadActionResult> {
    downloads
        .act_on_file(request, playback, operation, move |path, action| {
            let result = match action {
                DownloadAction::OpenFile => app.opener().open_path(
                    path.to_str().ok_or_else(|| {
                        AppError::new(ErrorCode::Storage, "文件路径不能转换为系统打开命令")
                    })?,
                    None::<&str>,
                ),
                DownloadAction::RevealFile => app.opener().reveal_item_in_dir(path),
                _ => unreachable!("only external file actions reach the opener"),
            };
            result.map_err(|error| {
                AppError::with_source(ErrorCode::Storage, "无法打开本机文件或所在文件夹", error)
            })
        })
        .await
}
