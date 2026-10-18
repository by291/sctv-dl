mod support;

use std::{sync::Arc, time::Duration};

use axum::{Router, body::Body, http::Response};
use sctv_dl_desktop_lib::{
    downloads::*,
    history::HistoryMetadata,
    lifecycle::ExitController,
    media::{PlaybackService, Quality},
};

async fn completed() -> (
    tempfile::TempDir,
    DownloadManager,
    DownloadTask,
    ExitController,
) {
    let server = support::serve(Router::new().fallback(|| async {
        Response::builder()
            .header("Content-Type", "video/mp4")
            .body(Body::from("local bytes"))
            .unwrap()
    }))
    .await;

    let root = tempfile::tempdir().unwrap();
    let dir = root.path().join("files");
    std::fs::create_dir(&dir).unwrap();
    let manager = DownloadManager::open(
        DownloadConfig {
            upstream_origins: vec![server.origin.clone()],
            ..Default::default()
        },
        root.path().join("downloads-v1.json"),
    )
    .await
    .unwrap();

    let content = ContentRef {
        programme_id: "1".into(),
        date_id: "2".into(),
        content_id: "3".into(),
    };

    manager
        .start(
            vec![PreparedDownload {
                content: content.clone(),
                metadata: HistoryMetadata {
                    content,
                    programme_name: "News".into(),
                    broadcast_date: "2026-10-17".into(),
                    title: "Clip".into(),
                    cover: None,
                },
                filename: "clip.mp4".into(),
                quality: Quality::Standard,
                url: format!("{}/clip.mp4", server.origin),
            }],
            &dir,
        )
        .await
        .unwrap();

    let task = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            let task = manager.list()[0].clone();
            if !task.active() {
                break task;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();

    assert_eq!(task.state, TaskState::Completed);
    (root, manager, task, ExitController::default())
}

fn request(task: &DownloadTask, action: DownloadAction) -> DownloadActionRequest {
    DownloadActionRequest {
        task_id: task.id.clone(),
        attempt_id: task.attempt_id.clone(),
        action,
    }
}

#[tokio::test]
async fn deleting_the_owned_file_stops_local_playback_and_retains_a_missing_record() {
    let (root, manager, task, gate) = completed().await;
    let playback = PlaybackService::new(Default::default()).await.unwrap();
    let session = manager
        .open_local_playback(
            task.id.clone(),
            playback.clone(),
            Arc::new(gate.enter().await.unwrap()),
        )
        .await
        .unwrap()
        .deliver();
    assert_eq!(
        reqwest::get(&session.sources[0].url)
            .await
            .unwrap()
            .status(),
        200
    );

    manager
        .act_on_file(
            request(&task, DownloadAction::DeleteFile),
            Some(playback.clone()),
            Arc::new(gate.enter().await.unwrap()),
            |_, _| panic!("deletion does not call an external opener"),
        )
        .await
        .unwrap();
    assert_eq!(manager.list()[0].state, TaskState::Missing);
    assert!(!root.path().join("files").join(task.filename).exists());
    assert_eq!(
        reqwest::get(&session.sources[0].url)
            .await
            .unwrap()
            .status(),
        404
    );

    playback.shutdown().await;
    manager.shutdown().await;
}

#[tokio::test]
async fn validates_external_paths_and_preserves_replacement_files() {
    let (root, manager, task, gate) = completed().await;
    let expected = root
        .path()
        .join("files")
        .join(&task.filename)
        .canonicalize()
        .unwrap();
    let observed = Arc::new(std::sync::Mutex::new(Vec::new()));
    for action in [DownloadAction::OpenFile, DownloadAction::RevealFile] {
        let observed = observed.clone();
        manager
            .act_on_file(
                request(&task, action),
                None,
                Arc::new(gate.enter().await.unwrap()),
                move |path, action| {
                    observed.lock().unwrap().push((path.to_owned(), action));
                    Ok(())
                },
            )
            .await
            .unwrap();
    }
    assert_eq!(observed.lock().unwrap().len(), 2);
    assert!(
        observed
            .lock()
            .unwrap()
            .iter()
            .all(|(path, _)| path == &expected)
    );

    std::fs::rename(&expected, root.path().join("original.mp4")).unwrap();
    std::fs::write(&expected, b"replacement").unwrap();
    assert!(
        manager
            .act_on_file(
                request(&task, DownloadAction::DeleteFile),
                None,
                Arc::new(gate.enter().await.unwrap()),
                |_, _| Ok(())
            )
            .await
            .is_err()
    );
    assert_eq!(std::fs::read(&expected).unwrap(), b"replacement");
    assert_eq!(manager.list()[0].state, TaskState::Missing);
    manager.shutdown().await;
}

#[tokio::test]
async fn removing_the_record_keeps_independent_playback_and_cancelled_open_results_close_the_session()
 {
    let (_root, manager, task, gate) = completed().await;
    let playback = PlaybackService::new(Default::default()).await.unwrap();
    let pending = manager
        .open_local_playback(
            task.id.clone(),
            playback.clone(),
            Arc::new(gate.enter().await.unwrap()),
        )
        .await
        .unwrap();
    drop(pending);
    let session = manager
        .open_local_playback(
            task.id.clone(),
            playback.clone(),
            Arc::new(gate.enter().await.unwrap()),
        )
        .await
        .unwrap()
        .deliver();
    manager
        .act(
            request(&task, DownloadAction::Remove),
            None,
            Arc::new(gate.enter().await.unwrap()),
        )
        .await
        .unwrap();

    assert!(manager.list().is_empty());
    assert_eq!(
        reqwest::get(&session.sources[0].url)
            .await
            .unwrap()
            .text()
            .await
            .unwrap(),
        "local bytes"
    );

    playback.shutdown().await;
    manager.shutdown().await;
}
