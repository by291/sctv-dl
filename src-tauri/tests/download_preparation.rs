mod support;

use axum::{Json, Router, http::Uri};
use sctv_dl_desktop_lib::{
    downloads::{DownloadConfig, DownloadManager, DownloadRequest},
    error::ErrorCode,
    media::Quality,
    programmes::{Deadlines, ProgrammeService},
};
use serde_json::{Value, json};

async fn programme_stub(contents: Value) -> (support::Stub, ProgrammeService) {
    let router = Router::new().fallback(move |uri: Uri| {
        let contents = contents.clone();
        async move {
            let data = if uri.path().contains("contents") {
                contents
            } else if uri.path() == "/app/v1/programs" {
                json!({ "records": [{ "id": 1, "name": "News" }] })
            } else {
                json!([{ "id": 2, "date": "2026-10-16" }])
            };
            Json(json!({ "rs": 200, "data": data }))
        }
    });
    let server = support::serve(router).await;
    let service = ProgrammeService::new(
        &server.origin,
        uuid::Uuid::new_v4().to_string(),
        Deadlines::default(),
    )
    .unwrap();

    (server, service)
}

fn request(ids: &[&str], quality: Quality) -> DownloadRequest {
    DownloadRequest {
        programme_id: "1".into(),
        date_id: "2".into(),
        content_ids: ids.iter().map(|id| (*id).into()).collect(),
        quality,
    }
}

#[tokio::test]
async fn resolves_broadcasts_isolates_missing_files_and_reports_actual_quality() {
    let (_server, service) = programme_stub(json!([
        { "id": 3, "title": "News:/Clip", "video": "https://fscgc.scgchc.com/a.mp4" },
        { "id": 4, "title": "Missing" },
        { "id": 5, "title": "Forbidden", "video": "https://evil.invalid/a.mp4" }
    ]))
    .await;
    let manager = DownloadManager::new(DownloadConfig::default()).unwrap();

    let batch = manager
        .prepare(
            &service,
            request(&["3", "4", "5", "6", "3"], Quality::Smooth),
        )
        .await
        .unwrap();

    assert_eq!(batch.files.len(), 1);
    assert_eq!(batch.files[0].content.content_id, "3");
    assert_eq!(batch.files[0].filename, "2026-10-16_News__Clip_标准.mp4");
    assert_eq!(batch.files[0].quality, Quality::Standard);
    assert!(batch.used_fallback);
    assert_eq!(
        batch
            .failures
            .iter()
            .map(|failure| failure.content_id.as_str())
            .collect::<Vec<_>>(),
        ["4", "5", "6"]
    );

    let mut stale = request(&["3"], Quality::Standard);
    stale.date_id = "99".into();
    assert_eq!(
        manager.prepare(&service, stale).await.err().unwrap().code,
        ErrorCode::NotFound
    );
    manager.shutdown().await;
}

#[tokio::test]
async fn preserves_requested_download_quality_for_duplicate_urls_and_reports_fallbacks() {
    let (_server, service) = programme_stub(json!([
        {
            "id": 3,
            "video": "https://fscgc.scgchc.com/standard.mp4",
            "videoStandard": "https://fscgc.scgchc.com/smooth.mp4"
        },
        { "id": 4, "video": "https://fscgc.scgchc.com/standard.mp4" },
        { "id": 5, "videoStandard": "https://fscgc.scgchc.com/smooth.mp4" },
        {
            "id": 6,
            "video": "https://fscgc.scgchc.com/same.mp4",
            "videoStandard": "https://fscgc.scgchc.com/same.mp4"
        }
    ]))
    .await;
    let manager = DownloadManager::new(DownloadConfig::default()).unwrap();

    for (id, requested, actual, fallback, url) in [
        (
            "3",
            Quality::Standard,
            Quality::Standard,
            false,
            "standard.mp4",
        ),
        ("3", Quality::Smooth, Quality::Smooth, false, "smooth.mp4"),
        (
            "4",
            Quality::Smooth,
            Quality::Standard,
            true,
            "standard.mp4",
        ),
        ("5", Quality::Standard, Quality::Smooth, true, "smooth.mp4"),
        ("6", Quality::Smooth, Quality::Smooth, false, "same.mp4"),
    ] {
        let batch = manager
            .prepare(&service, request(&[id], requested))
            .await
            .unwrap();
        assert_eq!(batch.files.len(), 1);
        assert!(batch.failures.is_empty());
        assert_eq!(batch.files[0].quality, actual);
        assert_eq!(batch.used_fallback, fallback);
        assert_eq!(
            batch.files[0].url,
            format!("https://fscgc.scgchc.com/{url}")
        );
    }

    manager.shutdown().await;
}

#[tokio::test]
async fn rejects_invalid_and_oversized_batches_before_network_access() {
    let manager = DownloadManager::new(DownloadConfig::default()).unwrap();
    let service =
        ProgrammeService::new("http://127.0.0.1:1", "guest".into(), Deadlines::default()).unwrap();

    for ids in [
        vec![],
        (0..101).map(|id| id.to_string()).collect(),
        vec!["../1".into()],
    ] {
        let mut request = request(&[], Quality::Standard);
        request.content_ids = ids;
        assert_eq!(
            manager.prepare(&service, request).await.err().unwrap().code,
            ErrorCode::InvalidInput
        );
    }
    manager.shutdown().await;
}

#[test]
fn rejects_caller_supplied_download_urls() {
    assert!(
        serde_json::from_value::<DownloadRequest>(json!({
            "programmeId": "1",
            "dateId": "2",
            "contentIds": ["3"],
            "quality": "standard",
            "url": "https://evil.invalid"
        }))
        .is_err()
    );
}
