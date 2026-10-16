use sctv_dl_desktop_lib::{
    downloads::{DownloadConfig, DownloadManager},
    lifecycle::ExitController,
};
use std::{sync::Arc, time::Duration};

#[tokio::test]
async fn exit_waits_for_inflight_operations_and_rejects_repeated_requests() {
    let controller = Arc::new(ExitController::default());
    let picker = controller.enter().await.unwrap();
    let request = controller.begin().unwrap();
    assert!(controller.begin().is_none());
    assert!(controller.enter().await.is_err());
    let downloads = DownloadManager::new(DownloadConfig::default()).unwrap();
    let completion = request.complete(&downloads, || async { panic!("no active downloads") });
    tokio::pin!(completion);
    assert!(
        tokio::time::timeout(Duration::from_millis(10), &mut completion)
            .await
            .is_err()
    );
    assert!(!controller.committed());
    drop(picker);
    assert!(completion.await);
    assert!(controller.committed());
    assert!(controller.enter().await.is_err());
}

#[tokio::test]
async fn rejecting_exit_reopens_operations_and_keeps_downloads_running() {
    use sctv_dl_desktop_lib::downloads::{ContentRef, PreparedDownload, TaskState};
    use sctv_dl_desktop_lib::media::Quality;
    let server = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", server.local_addr().unwrap());
    let server = tokio::spawn(async move {
        axum::serve(
            server,
            axum::Router::new().fallback(|| async { std::future::pending::<String>().await }),
        )
        .await
        .unwrap();
    });
    let root = tempfile::tempdir().unwrap();
    let downloads = DownloadManager::new(DownloadConfig {
        upstream_origin: origin.clone(),
        ..Default::default()
    })
    .unwrap();
    downloads
        .start(
            vec![PreparedDownload {
                content: ContentRef {
                    programme_id: "1".into(),
                    date_id: "2".into(),
                    content_id: "3".into(),
                },
                filename: "clip.mp4".into(),
                quality: Quality::Standard,
                url: format!("{origin}/clip.mp4"),
            }],
            root.path(),
        )
        .await
        .unwrap();
    let controller = Arc::new(ExitController::default());
    assert!(
        !controller
            .begin()
            .unwrap()
            .complete(&downloads, || async { false })
            .await
    );
    assert!(controller.enter().await.is_ok());
    assert!(downloads.has_active());
    assert!(
        controller
            .begin()
            .unwrap()
            .complete(&downloads, || async { true })
            .await
    );
    assert!(
        downloads
            .list()
            .iter()
            .all(|task| task.state == TaskState::Cancelled)
    );
    assert!(!std::fs::read_dir(root.path()).unwrap().any(|entry| {
        entry
            .unwrap()
            .path()
            .extension()
            .is_some_and(|ext| ext == "part" || ext == "json")
    }));
    assert!(sctv_dl_desktop_lib::downloads::files::DownloadDirectory::open(root.path()).is_ok());
    server.abort();
}

#[tokio::test]
async fn exit_allows_queued_settings_until_preparation_then_freezes_and_can_recover() {
    let controller = Arc::new(ExitController::default());
    let downloads = DownloadManager::new(DownloadConfig::default()).unwrap();
    let request = controller.begin().unwrap();
    let controller = &controller;
    let preparation = async {
        assert!(controller.enter().await.is_err());
        assert!(controller.enter_save().await.is_ok());
        false
    };
    assert!(
        !request
            .complete_prepared(&downloads, preparation, |saved| async move {
                assert!(!saved);
                assert!(controller.enter_save().await.is_err());
                false
            })
            .await
    );
    assert!(controller.enter_save().await.is_ok());
    assert!(
        controller
            .begin()
            .unwrap()
            .complete_prepared(&downloads, async { true }, |_| async {
                panic!("saved and idle")
            })
            .await
    );
    assert!(controller.enter_save().await.is_err());
}
