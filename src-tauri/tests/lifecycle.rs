use std::{sync::Arc, time::Duration};

use sctv_dl_desktop_lib::{
    downloads::{DownloadConfig, DownloadManager},
    lifecycle::ExitController,
};

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
        upstream_origins: vec![origin.clone()],
        ..Default::default()
    })
    .unwrap();
    downloads
        .start(
            vec![PreparedDownload {
                metadata: serde_json::from_value(serde_json::json!({
                    "content": {
                        "programmeId": "1",
                        "dateId": "2",
                        "contentId": "3"
                    },
                    "programmeName": "News",
                    "broadcastDate": "2026-10-17",
                    "title": "Clip",
                    "cover": null
                }))
                .unwrap(),
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

mod support;

async fn durable_download() -> (
    tempfile::TempDir,
    support::Stub,
    DownloadManager,
    std::path::PathBuf,
) {
    use axum::{Router, body::Body, http::Response};
    use sctv_dl_desktop_lib::downloads::PreparedDownload;

    let server = support::serve(Router::new().fallback(|| async {
        let body = futures_util::stream::once(async {
            Ok::<_, std::io::Error>(axum::body::Bytes::from_static(b"partial video bytes"))
        });
        let body = futures_util::StreamExt::chain(body, futures_util::stream::pending());
        Response::builder()
            .header("Content-Type", "video/mp4")
            .header("Content-Length", "1000000")
            .header("ETag", "\"stable\"")
            .body(Body::from_stream(body))
            .unwrap()
    }))
    .await;

    let root = tempfile::tempdir().unwrap();
    let target = root.path().join("files");
    std::fs::create_dir(&target).unwrap();
    let index = root.path().join("downloads-v1.json");
    let manager = DownloadManager::open(
        DownloadConfig {
            upstream_origins: vec![server.origin.clone()],
            ..Default::default()
        },
        index.clone(),
    )
    .await
    .unwrap();
    let metadata: sctv_dl_desktop_lib::history::HistoryMetadata =
        serde_json::from_value(serde_json::json!({
            "content": {
                "programmeId": "1",
                "dateId": "2",
                "contentId": "3"
            },
            "programmeName": "News",
            "broadcastDate": "2026-10-17",
            "title": "Clip",
            "cover": null
        }))
        .unwrap();
    manager
        .start(
            vec![PreparedDownload {
                content: metadata.content.clone(),
                metadata,
                filename: "clip.mp4".into(),
                quality: sctv_dl_desktop_lib::media::Quality::Standard,
                url: format!("{}/clip.mp4", server.origin),
            }],
            &target,
        )
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(5), async {
        while manager.list()[0].received_bytes == 0 {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap();
    (root, server, manager, index)
}

#[tokio::test]
async fn durable_exit_preserves_download_progress_and_does_not_restart_on_open() {
    let (_root, _server, manager, index) = durable_download().await;
    let controller = Arc::new(ExitController::default());
    assert!(
        controller
            .begin()
            .unwrap()
            .complete(&manager, || async { true })
            .await
    );

    let paused = manager.list()[0].clone();

    assert_eq!(
        paused.state,
        sctv_dl_desktop_lib::downloads::TaskState::Paused
    );
    assert!(paused.has_partial);
    assert!(paused.received_bytes > 0);

    drop(manager);
    let recovered = DownloadManager::open(Default::default(), index)
        .await
        .unwrap();
    assert!(!recovered.has_active());
    assert_eq!(recovered.list()[0].received_bytes, paused.received_bytes);
    assert!(recovered.list()[0].has_partial);
    recovered.shutdown().await;
}

#[tokio::test]
async fn failed_download_checkpoint_requires_a_separate_force_exit_decision() {
    let (_root, _server, manager, index) = durable_download().await;
    std::fs::rename(&index, index.with_extension("saved")).unwrap();
    std::fs::create_dir(&index).unwrap();
    let controller = Arc::new(ExitController::default());
    let force_offered = std::sync::atomic::AtomicBool::new(false);
    let exited = controller
        .begin()
        .unwrap()
        .complete_with_recovery(
            &manager,
            async { true },
            |_| async { true },
            |_| async {
                force_offered.store(true, std::sync::atomic::Ordering::SeqCst);
                false
            },
        )
        .await;
    assert!(!exited);
    assert!(force_offered.load(std::sync::atomic::Ordering::SeqCst));
    assert!(!controller.committed());
    assert!(controller.enter().await.is_ok());
    assert!(manager.list()[0].has_partial);

    force_offered.store(false, std::sync::atomic::Ordering::SeqCst);
    assert!(
        controller
            .begin()
            .unwrap()
            .complete_with_recovery(
                &manager,
                async { true },
                |_| async { true },
                |_| async {
                    force_offered.store(true, std::sync::atomic::Ordering::SeqCst);
                    true
                },
            )
            .await
    );
    assert!(force_offered.load(std::sync::atomic::Ordering::SeqCst));
    assert!(controller.committed());
    assert!(manager.list()[0].has_partial);
}
