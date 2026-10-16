use axum::{Json, Router, http::Uri};
use sctv_dl_desktop_lib::{
    downloads::{DownloadConfig, DownloadManager, DownloadRequest},
    media::Quality,
    programmes::{Deadlines, ProgrammeService},
};
use serde_json::json;

#[tokio::test]
async fn resolves_broadcasts_isolates_missing_files_and_reports_actual_quality() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let task = tokio::spawn(async move {
        axum::serve(
            listener,
            Router::new().fallback(|uri: Uri| async move {
                Json(json!({"rs":200,"data":if uri.path().contains("contents") {
            json!([
                {"id":3,"title":"News:/Clip","video":"https://fscgc.scgchc.com/a.mp4"},
                {"id":4,"title":"Missing"},
                {"id":5,"title":"Forbidden","video":"https://evil.invalid/a.mp4"}
            ])
        } else { json!([{"id":2,"date":"2026-10-16"}]) }}))
            }),
        )
        .await
        .unwrap();
    });
    let service = ProgrammeService::new(
        &origin,
        uuid::Uuid::new_v4().to_string(),
        Deadlines::default(),
    )
    .unwrap();
    let request = serde_json::from_value::<DownloadRequest>(json!({"programmeId":"1","dateId":"2","contentIds":["3","4","5","6","3"],"quality":"smooth"})).unwrap();
    let manager = DownloadManager::new(DownloadConfig::default()).unwrap();
    let batch = manager.prepare(&service, request).await.unwrap();
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
    let stale = serde_json::from_value::<DownloadRequest>(
        json!({"programmeId":"1","dateId":"99","contentIds":["3"],"quality":"standard"}),
    )
    .unwrap();
    assert_eq!(
        manager.prepare(&service, stale).await.err().unwrap().code,
        "not-found"
    );
    manager.shutdown().await;
    task.abort();
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
        let request = DownloadRequest {
            programme_id: "1".into(),
            date_id: "2".into(),
            content_ids: ids,
            quality: Quality::Standard,
        };
        assert_eq!(
            manager.prepare(&service, request).await.err().unwrap().code,
            "invalid-input"
        );
    }
    assert!(serde_json::from_value::<DownloadRequest>(json!({"programmeId":"1","dateId":"2","contentIds":["3"],"quality":"standard","url":"https://evil.invalid"})).is_err());
}
