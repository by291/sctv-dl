mod support;
use axum::{
    Router,
    body::{Body, Bytes},
    http::{Request, Response, StatusCode},
};
use sctv_dl_desktop_lib::{
    downloads::*, history::HistoryMetadata, lifecycle::ExitController, media::Quality,
};
use std::{
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

fn prepared(origin: &str) -> PreparedDownload {
    let content = ContentRef {
        programme_id: "1".into(),
        date_id: "2".into(),
        content_id: "3".into(),
    };
    PreparedDownload {
        metadata: HistoryMetadata {
            content: content.clone(),
            programme_name: "News".into(),
            broadcast_date: "2026-10-17".into(),
            title: "Clip".into(),
            cover: None,
        },
        content,
        filename: "clip.mp4".into(),
        quality: Quality::Standard,
        url: format!("{origin}/clip.mp4"),
    }
}
async fn act(
    manager: &DownloadManager,
    gate: &ExitController,
    task: &DownloadTask,
    action: DownloadAction,
    source: Option<PreparedDownload>,
) -> sctv_dl_desktop_lib::error::Result<DownloadActionResult> {
    manager
        .act(
            DownloadActionRequest {
                task_id: task.id.clone(),
                attempt_id: task.attempt_id.clone(),
                action,
            },
            source,
            Arc::new(gate.enter().await.unwrap()),
        )
        .await
}
async fn wait(
    manager: &DownloadManager,
    predicate: impl Fn(&DownloadTask) -> bool,
) -> DownloadTask {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if let Some(task) = manager.list().first()
                && predicate(task)
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
async fn pause_restart_recovery_and_valid_resume_preserve_exact_bytes_and_attempt_guards() {
    let bytes: Arc<Vec<u8>> = Arc::new((0..512 * 1024).map(|index| (index % 251) as u8).collect());
    let payload = bytes.clone();
    let requests = Arc::new(AtomicUsize::new(0));
    let observed = requests.clone();
    let server = support::serve(Router::new().fallback(move |request: Request<Body>| {
        let bytes = payload.clone();
        let requests = observed.clone();
        async move {
            requests.fetch_add(1, Ordering::SeqCst);
            if let Some(range) = request.headers().get("range") {
                assert_eq!(request.headers()["if-range"], "\"stable\"");
                let offset: usize = range
                    .to_str()
                    .unwrap()
                    .strip_prefix("bytes=")
                    .unwrap()
                    .trim_end_matches('-')
                    .parse()
                    .unwrap();
                return Response::builder()
                    .status(StatusCode::PARTIAL_CONTENT)
                    .header("Content-Type", "video/mp4")
                    .header("ETag", "\"stable\"")
                    .header(
                        "Content-Range",
                        format!("bytes {offset}-{}/{}", bytes.len() - 1, bytes.len()),
                    )
                    .body(Body::from(bytes[offset..].to_vec()))
                    .unwrap();
            }
            let length = bytes.len();
            let stream = futures_util::stream::unfold((bytes, 0), |(bytes, offset)| async move {
                if offset >= bytes.len() {
                    return None;
                }
                tokio::time::sleep(Duration::from_millis(25)).await;
                let end = (offset + 65536).min(bytes.len());
                Some((
                    Ok::<_, std::io::Error>(Bytes::copy_from_slice(&bytes[offset..end])),
                    (bytes, end),
                ))
            });
            Response::builder()
                .header("Content-Type", "video/mp4")
                .header("ETag", "\"stable\"")
                .header("Content-Length", length)
                .body(Body::from_stream(stream))
                .unwrap()
        }
    }))
    .await;
    let root = tempfile::tempdir().unwrap();
    let directory = root.path().join("files");
    std::fs::create_dir(&directory).unwrap();
    let index = root.path().join("downloads-v1.json");
    let config = || DownloadConfig {
        upstream_origins: vec![server.origin.clone()],
        ..Default::default()
    };
    let gate = ExitController::default();
    let manager = DownloadManager::open(config(), index.clone())
        .await
        .unwrap();
    manager
        .start(vec![prepared(&server.origin)], &directory)
        .await
        .unwrap();
    let running = wait(&manager, |task| task.received_bytes >= 65536).await;
    act(&manager, &gate, &running, DownloadAction::Pause, None)
        .await
        .unwrap();
    let paused = manager.list()[0].clone();
    assert_eq!(paused.state, TaskState::Paused);
    assert!(paused.can_resume);
    assert!(paused.has_partial);
    assert!(paused.received_bytes < bytes.len() as u64);
    assert!(matches!(
        act(&manager, &gate, &paused, DownloadAction::Pause, None)
            .await
            .unwrap(),
        DownloadActionResult::Skipped { .. }
    ));
    manager.shutdown().await;
    drop(manager);
    let count = requests.load(Ordering::SeqCst);
    let manager = DownloadManager::open(config(), index).await.unwrap();
    let interrupted = manager.list()[0].clone();
    assert_eq!(interrupted.state, TaskState::Interrupted);
    assert_eq!(interrupted.received_bytes, paused.received_bytes);
    assert_eq!(requests.load(Ordering::SeqCst), count);
    act(
        &manager,
        &gate,
        &interrupted,
        DownloadAction::Resume,
        Some(prepared(&server.origin)),
    )
    .await
    .unwrap();
    let completed = wait(&manager, |task| task.state == TaskState::Completed).await;
    assert_eq!(completed.id, paused.id);
    assert_ne!(completed.attempt_id, paused.attempt_id);
    assert!(completed.revision > paused.revision);
    assert_eq!(
        std::fs::read(directory.join(&completed.filename)).unwrap(),
        *bytes
    );
    assert!(matches!(
        act(&manager, &gate, &paused, DownloadAction::Cancel, None)
            .await
            .unwrap(),
        DownloadActionResult::Skipped { .. }
    ));
    manager.shutdown().await;
}

#[tokio::test]
async fn ignored_range_preserves_partial_and_requires_explicit_restart() {
    let total = 1024 * 1024;
    let server = support::serve(
        Router::new().fallback(move |request: Request<Body>| async move {
            if request.headers().contains_key("range") {
                return Response::builder()
                    .header("Content-Type", "video/mp4")
                    .header("ETag", "\"stable\"")
                    .body(Body::from(vec![b'x'; total]))
                    .unwrap();
            }
            let stream = futures_util::stream::unfold(0, move |offset| async move {
                if offset >= total {
                    return None;
                }
                tokio::time::sleep(Duration::from_millis(15)).await;
                Some((
                    Ok::<_, std::io::Error>(Bytes::from(vec![b'a'; 65536])),
                    offset + 65536,
                ))
            });
            Response::builder()
                .header("Content-Type", "video/mp4")
                .header("ETag", "\"stable\"")
                .header("Content-Length", total)
                .body(Body::from_stream(stream))
                .unwrap()
        }),
    )
    .await;
    let root = tempfile::tempdir().unwrap();
    let directory = root.path().join("files");
    std::fs::create_dir(&directory).unwrap();
    let manager = DownloadManager::open(
        DownloadConfig {
            upstream_origins: vec![server.origin.clone()],
            ..Default::default()
        },
        root.path().join("downloads-v1.json"),
    )
    .await
    .unwrap();
    let gate = ExitController::default();
    manager
        .start(vec![prepared(&server.origin)], &directory)
        .await
        .unwrap();
    let running = wait(&manager, |task| task.received_bytes >= 65536).await;
    act(&manager, &gate, &running, DownloadAction::Pause, None)
        .await
        .unwrap();
    let paused = manager.list()[0].clone();
    act(
        &manager,
        &gate,
        &paused,
        DownloadAction::Resume,
        Some(prepared(&server.origin)),
    )
    .await
    .unwrap();
    let failed = wait(&manager, |task| task.state == TaskState::Failed).await;
    assert_eq!(failed.received_bytes, paused.received_bytes);
    assert!(!failed.can_resume);
    assert!(failed.has_partial);
    act(
        &manager,
        &gate,
        &failed,
        DownloadAction::Restart,
        Some(prepared(&server.origin)),
    )
    .await
    .unwrap();
    let completed = wait(&manager, |task| task.state == TaskState::Completed).await;
    assert_eq!(completed.id, failed.id);
    assert_ne!(completed.attempt_id, failed.attempt_id);
    assert_eq!(
        std::fs::read(directory.join(completed.filename)).unwrap(),
        vec![b'a'; total]
    );
    manager.shutdown().await;
}

#[tokio::test]
async fn failed_checkpoint_blocks_repeated_quit_until_a_durable_retry_succeeds() {
    let server = support::serve(Router::new().fallback(|| async {
        let stream = futures_util::stream::unfold(0, |count| async move {
            tokio::time::sleep(Duration::from_millis(10)).await;
            Some((
                Ok::<_, std::io::Error>(Bytes::from(vec![b'a'; 1024])),
                count + 1,
            ))
        });
        Response::builder()
            .header("Content-Type", "video/mp4")
            .body(Body::from_stream(stream))
            .unwrap()
    }))
    .await;
    let root = tempfile::tempdir().unwrap();
    let directory = root.path().join("files");
    std::fs::create_dir(&directory).unwrap();
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
        .start(vec![prepared(&server.origin)], &directory)
        .await
        .unwrap();
    wait(&manager, |task| task.received_bytes > 0).await;
    let previous = std::fs::read(&path).unwrap();
    std::fs::remove_file(&path).unwrap();
    std::fs::create_dir(&path).unwrap();
    assert!(manager.prepare_shutdown().await.is_err());
    assert!(manager.prepare_shutdown().await.is_err());
    assert_eq!(manager.list()[0].state, TaskState::Failed);
    std::fs::remove_dir(&path).unwrap();
    std::fs::write(&path, previous).unwrap();
    let gate = ExitController::default();
    let failed = manager.list()[0].clone();
    act(&manager, &gate, &failed, DownloadAction::Cancel, None)
        .await
        .unwrap();
    assert!(manager.prepare_shutdown().await.is_ok());
    manager.shutdown().await;
}
