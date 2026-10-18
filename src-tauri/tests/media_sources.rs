mod support;

use axum::{Json, Router, http::Uri};
use sctv_dl_desktop_lib::{
    downloads::{DownloadConfig, DownloadManager, DownloadRequest},
    media::{MediaConfig, PlaybackRequest, PlaybackService, Quality},
    programmes::{Deadlines, ProgrammeService},
};
use serde_json::json;

#[tokio::test]
async fn prepares_playback_and_downloads_from_each_verified_cdn() {
    for host in ["fscgc.scgchc.com", "fscgc.sctv-tf.com"] {
        let url = format!("https://{host}/NewsTV/2021/02/09/archive.mp4");
        let video = url.clone();
        let upstream = support::serve(Router::new().fallback(move |uri: Uri| {
            let video = video.clone();
            async move {
                let data = if uri.path().contains("contents") {
                    json!([{ "id": 3, "title": "Archive", "video": video }])
                } else if uri.path() == "/app/v1/programs" {
                    json!({ "records": [{ "id": 1, "name": "News" }] })
                } else {
                    json!([{ "id": 2, "date": "2021-02-05" }])
                };
                Json(json!({ "rs": 200, "data": data }))
            }
        }))
        .await;
        let programmes =
            ProgrammeService::new(&upstream.origin, "guest".into(), Deadlines::default()).unwrap();
        let playback = PlaybackService::new(MediaConfig::default()).await.unwrap();
        let downloads = DownloadManager::new(DownloadConfig::default()).unwrap();

        let session = playback
            .open(
                &programmes,
                PlaybackRequest {
                    programme_id: "1".into(),
                    date_id: "2".into(),
                    content_id: "3".into(),
                    quality: Quality::Standard,
                },
            )
            .await;
        let batch = downloads
            .prepare(
                &programmes,
                DownloadRequest {
                    programme_id: "1".into(),
                    date_id: "2".into(),
                    content_ids: vec!["3".into()],
                    quality: Quality::Standard,
                },
            )
            .await;

        // Shut down service owners even when a regression makes preparation fail.
        playback.shutdown().await;
        downloads.shutdown().await;

        let session = session.unwrap();
        assert_eq!(session.sources.len(), 1);
        assert_eq!(session.selected_quality, Quality::Standard);
        assert!(session.sources[0].url.starts_with("http://127.0.0.1:"));
        let batch = batch.unwrap();
        assert!(batch.failures.is_empty());
        assert_eq!(batch.files.len(), 1);
        assert_eq!(batch.files[0].url, url);
        assert_eq!(batch.files[0].quality, Quality::Standard);
    }
}
