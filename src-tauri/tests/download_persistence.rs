mod support;
use axum::{Router, body::Body, http::Response};
use sctv_dl_desktop_lib::{downloads::*, lifecycle::ExitController, media::Quality};
use std::{sync::Arc, time::Duration};

fn prepared(origin: &str, id: &str) -> PreparedDownload {
    let content = ContentRef {
        programme_id: "1".into(),
        date_id: "2".into(),
        content_id: id.into(),
    };
    PreparedDownload {
        content: content.clone(),
        metadata: sctv_dl_desktop_lib::history::HistoryMetadata {
            content,
            programme_name: "News".into(),
            broadcast_date: "2026-10-17".into(),
            title: "Clip".into(),
            cover: None,
        },
        filename: "clip.mp4".into(),
        quality: Quality::Standard,
        url: format!("{origin}/clip.mp4"),
    }
}
async fn settled(manager: &DownloadManager) -> DownloadTask {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if let Some(task) = manager.list().first()
                && !task.active()
            {
                break task.clone();
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap()
}

#[tokio::test]
async fn completed_tasks_reload_without_network_and_removal_preserves_the_file() {
    let server = support::serve(Router::new().fallback(|| async {
        Response::builder()
            .header("Content-Type", "video/mp4")
            .header("ETag", "\"stable\"")
            .body(Body::from("complete bytes"))
            .unwrap()
    }))
    .await;
    let root = tempfile::tempdir().unwrap();
    let target = root.path().join("files");
    std::fs::create_dir(&target).unwrap();
    let path = root.path().join("downloads-v1.json");
    let manager = DownloadManager::open(
        DownloadConfig {
            upstream_origins: vec![server.origin.clone()],
            ..Default::default()
        },
        path.clone(),
    )
    .await
    .unwrap();
    manager
        .start(vec![prepared(&server.origin, "3")], &target)
        .await
        .unwrap();
    let complete = settled(&manager).await;
    assert_eq!(complete.state, TaskState::Completed);
    assert!(complete.file_available);
    assert!(!complete.has_partial);
    let epoch = manager.snapshot().unwrap().epoch;
    manager.shutdown().await;
    drop(manager);
    drop(server);
    let manager = DownloadManager::open(Default::default(), path)
        .await
        .unwrap();
    let reloaded = manager.list()[0].clone();
    assert_eq!(reloaded.id, complete.id);
    assert_eq!(reloaded.state, TaskState::Completed);
    assert_ne!(manager.snapshot().unwrap().epoch, epoch);
    let gate = Arc::new(ExitController::default());
    let events = Arc::new(std::sync::Mutex::new(Vec::new()));
    let received = events.clone();
    manager
        .subscribe_events(move |event| {
            received.lock().unwrap().push(event);
            true
        })
        .unwrap();
    manager
        .act(
            DownloadActionRequest {
                task_id: reloaded.id,
                attempt_id: reloaded.attempt_id,
                action: DownloadAction::Remove,
            },
            None,
            Arc::new(gate.enter().await.unwrap()),
        )
        .await
        .unwrap();
    assert!(manager.list().is_empty());
    assert_eq!(
        std::fs::read(target.join(&complete.filename)).unwrap(),
        b"complete bytes"
    );
    assert!(matches!(
        events.lock().unwrap()[0],
        DownloadEvent::Remove { .. }
    ));
    manager.shutdown().await;
}

#[tokio::test]
async fn corrupt_or_locked_indexes_disable_downloads_without_touching_download_directories() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("downloads-v1.json");
    std::fs::write(&path, b"{broken").unwrap();
    let manager = DownloadManager::open(Default::default(), path.clone())
        .await
        .unwrap();
    assert!(manager.snapshot().is_err());
    let target = root.path().join("untouched");
    std::fs::create_dir(&target).unwrap();
    assert!(manager.start(vec![], &target).await.is_err());
    assert_eq!(std::fs::read_dir(&target).unwrap().count(), 0);
    assert_eq!(std::fs::read(&path).unwrap(), b"{broken");
    manager.shutdown().await;
    drop(manager);
    std::fs::remove_file(&path).unwrap();
    let first = DownloadManager::open(Default::default(), path.clone())
        .await
        .unwrap();
    let second = DownloadManager::open(Default::default(), path)
        .await
        .unwrap();
    assert!(first.snapshot().is_ok());
    assert!(second.snapshot().is_err());
    first.shutdown().await;
    second.shutdown().await;
}

#[tokio::test]
async fn failed_admission_does_not_accept_tasks_or_leave_owned_artifacts() {
    let root = tempfile::tempdir().unwrap();
    let target = root.path().join("files");
    std::fs::create_dir(&target).unwrap();
    let path = root.path().join("downloads-v1.json");
    let manager = DownloadManager::open(Default::default(), path.clone())
        .await
        .unwrap();
    std::fs::create_dir(&path).unwrap();
    let result = manager
        .start(vec![prepared("https://fscgc.scgchc.com", "3")], &target)
        .await
        .unwrap();
    assert!(result.task_ids.is_empty());
    assert_eq!(result.failures.len(), 1);
    assert!(manager.list().is_empty());
    assert_eq!(std::fs::read_dir(&target).unwrap().count(), 1);
    manager.shutdown().await;
}
