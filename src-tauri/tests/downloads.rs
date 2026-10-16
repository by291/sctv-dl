use sctv_dl_desktop_lib::downloads::files::{DownloadDirectory, download_filename};
use sctv_dl_desktop_lib::media::Quality;
use std::{io::Write, sync::Arc};

use axum::{
    Router,
    body::Body,
    http::{Request, Response},
};
use sctv_dl_desktop_lib::downloads::{
    ContentRef, DownloadConfig, DownloadManager, PreparedDownload, TaskState,
};
use std::{
    sync::{
        Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

struct Stub {
    origin: String,
    task: tokio::task::JoinHandle<()>,
}
impl Drop for Stub {
    fn drop(&mut self) {
        self.task.abort();
    }
}
async fn stub(router: Router) -> Stub {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let task = tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    Stub { origin, task }
}
fn prepared(origin: &str, id: &str) -> PreparedDownload {
    PreparedDownload {
        content: ContentRef {
            programme_id: "1".into(),
            date_id: "2".into(),
            content_id: id.into(),
        },
        filename: "clip.mp4".into(),
        quality: Quality::Standard,
        url: format!("{origin}/{id}.mp4"),
    }
}
async fn terminal(manager: &DownloadManager, count: usize) {
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            let tasks = manager.list();
            if tasks.len() == count && tasks.iter().all(|task| task.state.is_terminal()) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("downloads did not reach terminal state");
}

#[tokio::test]
async fn rejects_start_after_shutdown_without_reopening_the_directory() {
    let root = tempfile::tempdir().unwrap();
    let manager = DownloadManager::new(DownloadConfig::default()).unwrap();
    manager.shutdown().await;
    assert!(
        manager
            .start(vec![prepared("https://fscgc.scgchc.com", "3")], root.path())
            .await
            .is_err()
    );
    assert!(!root.path().join(".sctv-dl.lock").exists());
    assert!(DownloadDirectory::open(root.path()).is_ok());
}

#[test]
fn shutdown_waits_for_delayed_directory_preparation() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .max_blocking_threads(1)
        .build()
        .unwrap();
    runtime.block_on(async {
        let root = tempfile::tempdir().unwrap();
        let manager = DownloadManager::new(DownloadConfig::default()).unwrap();
        let (release, waiting) = std::sync::mpsc::channel();
        let (ready, started) = tokio::sync::oneshot::channel();
        let blocker = tokio::task::spawn_blocking(move || {
            ready.send(()).unwrap();
            waiting.recv().unwrap();
        });
        started.await.unwrap();
        let start = manager.start(Vec::new(), root.path());
        tokio::pin!(start);
        assert!(
            tokio::time::timeout(Duration::from_millis(10), &mut start)
                .await
                .is_err()
        );
        let shutdown = manager.shutdown();
        tokio::pin!(shutdown);
        let returned_early = tokio::time::timeout(Duration::from_millis(10), &mut shutdown)
            .await
            .is_ok();
        release.send(()).unwrap();
        blocker.await.unwrap();
        if !returned_early {
            shutdown.await;
        }
        assert!(start.await.is_err());
        assert!(
            !returned_early,
            "shutdown returned before queued preparation settled"
        );
        assert!(DownloadDirectory::open(root.path()).is_ok());
    });
}

fn replace_temporary_file(root: &std::path::Path) -> std::path::PathBuf {
    let temporary = std::fs::read_dir(root)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .find(|path| {
            path.extension()
                .is_some_and(|extension| extension == "part")
        })
        .unwrap();
    std::fs::remove_file(&temporary).unwrap();
    std::fs::write(&temporary, b"unrelated replacement").unwrap();
    temporary
}

#[test]
fn finalization_preserves_a_regular_file_replacing_the_temporary_path() {
    let root = tempfile::tempdir().unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let (mut file, reservation) = directory.reserve("clip.mp4").unwrap();
    file.write_all(b"downloaded bytes").unwrap();
    drop(file);
    let replacement = replace_temporary_file(root.path());
    assert!(reservation.finish().is_err());
    assert_eq!(
        std::fs::read(replacement).unwrap(),
        b"unrelated replacement"
    );
    assert!(!root.path().join("clip.mp4").exists());
}

#[test]
fn cancellation_preserves_a_regular_file_replacing_the_temporary_path() {
    let root = tempfile::tempdir().unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let (file, reservation) = directory.reserve("clip.mp4").unwrap();
    drop(file);
    let replacement = replace_temporary_file(root.path());
    assert!(reservation.cleanup().is_err());
    assert_eq!(
        std::fs::read(&replacement).unwrap(),
        b"unrelated replacement"
    );
    drop(directory);
    // A handled live replacement must not be mistaken for a crash leftover on next open.
    drop(DownloadDirectory::open(root.path()).unwrap());
    assert_eq!(
        std::fs::read(replacement).unwrap(),
        b"unrelated replacement"
    );
}

#[tokio::test]
async fn completes_only_after_saving_exact_bytes_and_preserves_media_headers() {
    let server = stub(Router::new().fallback(|request: Request<Body>| async move {
        assert_eq!(request.headers()["referer"], "https://scgc.video.play/");
        assert_eq!(request.headers()["accept-encoding"], "identity");
        assert!(!request.headers().contains_key("deviceid"));
        assert!(!request.headers().contains_key("cookie"));
        Response::builder()
            .header("Content-Type", "video/mp4")
            .body(Body::from("small mp4 fixture"))
            .unwrap()
    }))
    .await;
    let root = tempfile::tempdir().unwrap();
    let manager = DownloadManager::new(DownloadConfig {
        upstream_origin: server.origin.clone(),
        ..DownloadConfig::default()
    })
    .unwrap();
    let directory = root.path().to_owned();
    let observed = Arc::new(Mutex::new(Vec::new()));
    let capture = observed.clone();
    manager.subscribe(move |task| {
        if task.state == TaskState::Completed {
            assert_eq!(
                std::fs::read(directory.join(&task.filename)).unwrap(),
                b"small mp4 fixture"
            );
        }
        capture.lock().unwrap().push(task);
        true
    });
    let result = manager
        .start(vec![prepared(&server.origin, "3")], root.path())
        .await
        .unwrap();
    assert_eq!(result.task_ids.len(), 1);
    terminal(&manager, 1).await;
    let task = manager.list().pop().unwrap();
    assert_eq!(task.state, TaskState::Completed);
    assert_eq!(task.received_bytes, 17);
    assert_eq!(
        std::fs::read(root.path().join(&task.filename)).unwrap(),
        b"small mp4 fixture"
    );
    let revisions: Vec<_> = observed
        .lock()
        .unwrap()
        .iter()
        .map(|task| task.revision)
        .collect();
    assert!(revisions.iter().all(|revision| *revision > 0));
    assert!(revisions.windows(2).all(|pair| pair[1] > pair[0]));
    manager.shutdown().await;
}

#[tokio::test]
async fn limits_concurrency_deduplicates_active_jobs_and_cancels_waiting_jobs() {
    let calls = Arc::new(AtomicUsize::new(0));
    let seen = calls.clone();
    let server = stub(Router::new().fallback(move || {
        seen.fetch_add(1, Ordering::SeqCst);
        async { std::future::pending::<Response<Body>>().await }
    }))
    .await;
    let root = tempfile::tempdir().unwrap();
    let manager = DownloadManager::new(DownloadConfig {
        upstream_origin: server.origin.clone(),
        ..DownloadConfig::default()
    })
    .unwrap();
    let files = (3..7)
        .map(|id| prepared(&server.origin, &id.to_string()))
        .collect();
    let result = manager.start(files, root.path()).await.unwrap();
    tokio::time::timeout(Duration::from_secs(1), async {
        while calls.load(Ordering::SeqCst) != 2 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let duplicate = manager
        .start(vec![prepared(&server.origin, "3")], root.path())
        .await
        .unwrap();
    assert_eq!(duplicate.task_ids, vec![result.task_ids[0].clone()]);
    let queued = manager
        .list()
        .into_iter()
        .find(|task| task.state == TaskState::Queued)
        .unwrap();
    manager.cancel(&queued.id);
    tokio::time::timeout(Duration::from_secs(1), async {
        while manager
            .list()
            .iter()
            .find(|task| task.id == queued.id)
            .unwrap()
            .state
            != TaskState::Cancelled
        {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    manager.shutdown().await;
    assert!(
        manager
            .list()
            .iter()
            .all(|task| task.state == TaskState::Cancelled)
    );
    assert!(
        manager
            .start(vec![prepared(&server.origin, "7")], root.path())
            .await
            .is_err()
    );
    assert!(!std::fs::read_dir(root.path()).unwrap().any(|entry| {
        entry
            .unwrap()
            .path()
            .extension()
            .is_some_and(|ext| ext == "part" || ext == "json")
    }));
}

#[tokio::test]
async fn isolates_transfer_failures_and_keeps_unknown_totals_unknown() {
    let server = stub(Router::new().fallback(|request: Request<Body>| async move {
        match request.uri().path() {
            "/3.mp4" => Response::builder()
                .header("Content-Type", "text/html")
                .body(Body::from("not a video"))
                .unwrap(),
            "/4.mp4" => Response::builder()
                .status(302)
                .header("Location", "/5.mp4")
                .body(Body::empty())
                .unwrap(),
            "/5.mp4" => Response::builder()
                .header("Content-Type", "video/mp4")
                .header("Content-Length", 100)
                .body(Body::from_stream(futures_util::stream::iter([
                    Ok::<_, std::io::Error>(vec![1_u8; 10]),
                    Err(std::io::Error::other("interrupted")),
                ])))
                .unwrap(),
            _ => Response::builder()
                .header("Content-Type", "video/mp4")
                .body(Body::from_stream(futures_util::stream::iter([Ok::<
                    _,
                    std::io::Error,
                >(
                    b"unknown length".to_vec(),
                )])))
                .unwrap(),
        }
    }))
    .await;
    let root = tempfile::tempdir().unwrap();
    let manager = DownloadManager::new(DownloadConfig {
        upstream_origin: server.origin.clone(),
        ..DownloadConfig::default()
    })
    .unwrap();
    manager
        .start(
            (3..7)
                .map(|id| prepared(&server.origin, &id.to_string()))
                .collect(),
            root.path(),
        )
        .await
        .unwrap();
    terminal(&manager, 4).await;
    let tasks = manager.list();
    assert_eq!(
        tasks
            .iter()
            .filter(|task| task.state == TaskState::Failed)
            .count(),
        3
    );
    let completed = tasks
        .iter()
        .find(|task| task.state == TaskState::Completed)
        .unwrap();
    assert_eq!(completed.total_bytes, None);
    assert_eq!(
        std::fs::read(root.path().join(&completed.filename)).unwrap(),
        b"unknown length"
    );
    manager.shutdown().await;
}

#[tokio::test]
async fn bounds_outstanding_work_and_releases_a_cancelled_slot_for_waiting_downloads() {
    let server =
        stub(Router::new().fallback(|| async { std::future::pending::<Response<Body>>().await }))
            .await;
    let root = tempfile::tempdir().unwrap();
    let manager = DownloadManager::new(DownloadConfig {
        upstream_origin: server.origin.clone(),
        queue_capacity: 2,
        ..DownloadConfig::default()
    })
    .unwrap();
    let first = manager
        .start(
            vec![prepared(&server.origin, "3"), prepared(&server.origin, "4")],
            root.path(),
        )
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(1), async {
        while manager
            .list()
            .iter()
            .filter(|task| task.state == TaskState::Running)
            .count()
            != 2
        {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let second = manager
        .start(
            vec![
                prepared(&server.origin, "5"),
                prepared(&server.origin, "6"),
                prepared(&server.origin, "7"),
            ],
            root.path(),
        )
        .await
        .unwrap();
    assert_eq!(second.task_ids.len(), 2);
    assert_eq!(second.failures.len(), 1);
    manager.cancel(&first.task_ids[0]);
    tokio::time::timeout(Duration::from_secs(1), async {
        while !manager
            .list()
            .iter()
            .any(|task| second.task_ids.contains(&task.id) && task.state == TaskState::Running)
        {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    manager.shutdown().await;
}

#[tokio::test]
async fn throttles_progress_and_keeps_the_latest_written_count_when_cancelled() {
    let server = stub(Router::new().fallback(|| async {
        let stream = futures_util::stream::unfold(0, |index| async move {
            tokio::time::sleep(Duration::from_millis(10)).await;
            Some((Ok::<_, std::io::Error>(vec![1_u8; 1024]), index + 1))
        });
        Response::builder()
            .header("Content-Type", "video/mp4")
            .body(Body::from_stream(stream))
            .unwrap()
    }))
    .await;
    let root = tempfile::tempdir().unwrap();
    let manager = DownloadManager::new(DownloadConfig {
        upstream_origin: server.origin.clone(),
        ..DownloadConfig::default()
    })
    .unwrap();
    let events = Arc::new(Mutex::new(Vec::new()));
    let capture = events.clone();
    manager.subscribe(move |task| {
        capture
            .lock()
            .unwrap()
            .push((std::time::Instant::now(), task));
        true
    });
    let start = manager
        .start(vec![prepared(&server.origin, "3")], root.path())
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(270)).await;
    manager.cancel(&start.task_ids[0]);
    terminal(&manager, 1).await;
    let final_task = manager.list().pop().unwrap();
    assert_eq!(final_task.state, TaskState::Cancelled);
    {
        let events = events.lock().unwrap();
        let progress: Vec<_> = events
            .iter()
            .filter(|(_, task)| task.state == TaskState::Running && task.received_bytes > 0)
            .collect();
        assert!(progress.len() >= 2);
        assert!(
            progress
                .windows(2)
                .all(|pair| pair[1].0.duration_since(pair[0].0) >= Duration::from_millis(100))
        );
        assert!(final_task.received_bytes > progress.last().unwrap().1.received_bytes);
    }
    manager.shutdown().await;
}

#[test]
fn reports_finalization_and_cleanup_failures_instead_of_overwriting_replaced_artifacts() {
    let root = tempfile::tempdir().unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let (file, reservation) = directory.reserve("clip.mp4").unwrap();
    drop(file);
    let temporary = std::fs::read_dir(root.path())
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .find(|path| {
            path.extension()
                .is_some_and(|extension| extension == "part")
        })
        .unwrap();
    std::fs::remove_file(&temporary).unwrap();
    std::fs::create_dir(&temporary).unwrap();
    assert!(reservation.cleanup().is_err());
    assert!(temporary.is_dir());
    std::fs::remove_dir(&temporary).unwrap();
    let (file, reservation) = directory.reserve("another.mp4").unwrap();
    drop(file);
    let temporary = std::fs::read_dir(root.path())
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .find(|path| {
            path.extension()
                .is_some_and(|extension| extension == "part")
        })
        .unwrap();
    std::fs::remove_file(&temporary).unwrap();
    assert!(reservation.finish().is_err());
    assert!(!root.path().join("another.mp4").exists());
}

#[test]
fn handles_windows_superscript_device_names_and_rejects_paths_without_tempfile_room() {
    let root = tempfile::tempdir().unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let (file, reservation) = directory.reserve("LPT².mp4").unwrap();
    assert_eq!(reservation.filename(), "_LPT².mp4");
    drop(file);
    reservation.cleanup().unwrap();
    let mut long = root.path().to_owned();
    while long.as_os_str().to_string_lossy().encode_utf16().count() < 190 {
        long.push("123456789012345678901234567890");
    }
    std::fs::create_dir_all(&long).unwrap();
    let directory = DownloadDirectory::open(&long).unwrap();
    assert!(directory.reserve("clip.mp4").is_err());
}

#[test]
fn refuses_to_finalize_a_temporary_path_replaced_by_a_directory() {
    let root = tempfile::tempdir().unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let (file, reservation) = directory.reserve("clip.mp4").unwrap();
    drop(file);
    let temporary = std::fs::read_dir(root.path())
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .find(|path| {
            path.extension()
                .is_some_and(|extension| extension == "part")
        })
        .unwrap();
    std::fs::remove_file(&temporary).unwrap();
    std::fs::create_dir(&temporary).unwrap();
    assert!(reservation.finish().is_err());
    assert!(temporary.is_dir());
    assert!(!root.path().join("clip.mp4").exists());
}

#[cfg(target_os = "macos")]
#[test]
fn treats_a_normalization_equivalent_dangling_symlink_as_an_occupied_name() {
    let root = tempfile::tempdir().unwrap();
    let occupied = root.path().join("e\u{301}.mp4");
    std::os::unix::fs::symlink("missing", occupied).unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let (file, reservation) = directory.reserve("é.mp4").unwrap();
    assert_eq!(reservation.filename(), "é (1).mp4");
    drop(file);
    reservation.cleanup().unwrap();
}

#[test]
fn derives_portable_names_without_splitting_unicode() {
    let fixtures: serde_json::Value =
        serde_json::from_str(include_str!("../../shared/fixtures/download-names.json")).unwrap();
    for row in fixtures.as_array().unwrap() {
        assert_eq!(
            download_filename(
                row["date"].as_str().unwrap(),
                row["title"].as_str().unwrap(),
                Quality::Standard
            ),
            row["filename"].as_str().unwrap()
        );
    }
    let name = download_filename("2026-10-16", &"🎥".repeat(200), Quality::Smooth);
    assert!(name.ends_with(".mp4"));
    assert!(name.encode_utf16().count() <= 154);
    assert!(!name.contains('\u{fffd}'));
}

#[test]
fn reserves_case_insensitive_names_and_preserves_existing_bytes() {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("NEWS.mp4"), b"original").unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let (mut first, reserved) = directory.reserve("news.mp4").unwrap();
    let (mut second, another) = directory.reserve("news.mp4").unwrap();
    assert_eq!(reserved.filename(), "news (1).mp4");
    assert_eq!(another.filename(), "news (2).mp4");
    first.write_all(b"one").unwrap();
    second.write_all(b"two").unwrap();
    drop(first);
    drop(second);
    assert_eq!(reserved.finish().unwrap(), "news (1).mp4");
    assert_eq!(another.finish().unwrap(), "news (2).mp4");
    assert_eq!(
        std::fs::read(root.path().join("NEWS.mp4")).unwrap(),
        b"original"
    );
    assert_eq!(
        std::fs::read(root.path().join("news (1).mp4")).unwrap(),
        b"one"
    );
    assert_eq!(
        std::fs::read(root.path().join("news (2).mp4")).unwrap(),
        b"two"
    );
}

#[test]
fn finalization_never_clobbers_a_destination_created_during_transfer() {
    let root = tempfile::tempdir().unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let (mut file, reserved) = directory.reserve("clip.mp4").unwrap();
    file.write_all(b"download").unwrap();
    drop(file);
    std::fs::write(root.path().join("clip.mp4"), b"external").unwrap();
    assert_eq!(reserved.finish().unwrap(), "clip (1).mp4");
    assert_eq!(
        std::fs::read(root.path().join("clip.mp4")).unwrap(),
        b"external"
    );
    assert_eq!(
        std::fs::read(root.path().join("clip (1).mp4")).unwrap(),
        b"download"
    );
}

#[test]
fn releases_cancelled_reservations_and_only_recovers_recognized_leftovers() {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join(".sctv-dl-unrelated.part"), b"keep").unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let (file, reserved) = directory.reserve("clip.mp4").unwrap();
    drop(file);
    reserved.cleanup().unwrap();
    drop(directory);
    let id = "11111111-1111-4111-8111-111111111111";
    let part = root.path().join(format!(".sctv-dl-{id}.part"));
    std::fs::write(&part, b"interrupted").unwrap();
    let journal = root.path().join(format!(".sctv-dl-{id}.json"));
    std::fs::write(&journal, format!(r#"{{"sctvDlDownload":1,"id":"{id}"}}"#)).unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    assert!(!part.exists());
    assert!(!journal.exists());
    let (file, reserved) = directory.reserve("clip.mp4").unwrap();
    assert_eq!(reserved.filename(), "clip.mp4");
    drop(file);
    reserved.cleanup().unwrap();
    assert_eq!(
        std::fs::read(root.path().join(".sctv-dl-unrelated.part")).unwrap(),
        b"keep"
    );
}

#[test]
fn preserves_unrecognized_recovery_records_and_their_temporary_files() {
    let fixtures = [
        (
            "11111111-1111-4111-8111-111111111111",
            r#"{"sctvDlDownload":2,"id":"11111111-1111-4111-8111-111111111111"}"#,
        ),
        (
            "11111111-1111-4111-8111-111111111111",
            r#"{"sctvDlDownload":1,"id":"22222222-2222-4222-8222-222222222222"}"#,
        ),
        ("11111111-1111-4111-8111-111111111111", "{interrupted"),
        ("not-a-uuid", r#"{"sctvDlDownload":1,"id":"not-a-uuid"}"#),
    ];

    for (id, record) in fixtures {
        let root = tempfile::tempdir().unwrap();
        let temporary = root.path().join(format!(".sctv-dl-{id}.part"));
        let journal = root.path().join(format!(".sctv-dl-{id}.json"));
        std::fs::write(&temporary, b"unrecognized bytes").unwrap();
        std::fs::write(&journal, record).unwrap();

        let _directory = DownloadDirectory::open(root.path()).unwrap();

        assert_eq!(std::fs::read(&temporary).unwrap(), b"unrecognized bytes");
        assert_eq!(std::fs::read_to_string(&journal).unwrap(), record);
    }
}

#[test]
fn simultaneous_reservations_are_unique_and_invalid_directories_fail() {
    let root = tempfile::tempdir().unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let threads: Vec<_> = (0..8)
        .map(|_| {
            let directory = Arc::clone(&directory);
            std::thread::spawn(move || directory.reserve("CON.mp4").unwrap())
        })
        .collect();
    let reservations: Vec<_> = threads
        .into_iter()
        .map(|thread| thread.join().unwrap())
        .collect();
    let mut names: Vec<_> = reservations
        .iter()
        .map(|(_, reserved)| reserved.filename().to_owned())
        .collect();
    names.sort();
    names.dedup();
    assert_eq!(names.len(), 8);
    assert!(names.iter().all(|name| name.starts_with("_CON")));
    for (file, reserved) in reservations {
        drop(file);
        reserved.cleanup().unwrap();
    }
    assert!(DownloadDirectory::open(&root.path().join("missing")).is_err());
    std::fs::write(root.path().join("file"), b"file").unwrap();
    assert!(DownloadDirectory::open(&root.path().join("file")).is_err());
}
