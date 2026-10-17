use sctv_dl_desktop_lib::downloads::files::DownloadDirectory;
use std::io::Write;

#[test]
fn resumes_only_the_index_checkpoint_and_preserves_replacements() {
    let root = tempfile::tempdir().unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let (mut file, mut reservation) = directory.reserve("clip.mp4").unwrap();
    let initial = reservation
        .upgrade("task".into(), "attempt".into())
        .unwrap();
    file.write_all(&vec![b'a'; 1024 * 1024]).unwrap();
    file.flush().unwrap();
    let checkpoint = reservation
        .checkpoint(
            1024 * 1024,
            Some(2 * 1024 * 1024),
            Some("\"stable\"".into()),
        )
        .unwrap();
    file.write_all(b"uncommitted tail").unwrap();
    file.flush().unwrap();
    // A crash may leave the journal ahead of the private index.
    reservation
        .checkpoint(
            1024 * 1024 + 16,
            Some(2 * 1024 * 1024),
            Some("\"stable\"".into()),
        )
        .unwrap();
    drop(file);
    reservation.retain();
    drop(directory);
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let restored = directory.recover_reservation(&checkpoint).unwrap();
    let path = root.path().join(format!(".sctv-dl-{}.part", initial.id));
    assert_eq!(std::fs::metadata(&path).unwrap().len(), 1024 * 1024);
    restored.retain();
    std::fs::remove_file(&path).unwrap();
    std::fs::write(&path, b"replacement").unwrap();
    assert!(directory.recover_reservation(&checkpoint).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), b"replacement");
}

#[test]
fn preserves_short_files_unknown_journals_and_symlink_replacements() {
    let root = tempfile::tempdir().unwrap();
    let directory = DownloadDirectory::open(root.path()).unwrap();
    let (mut file, mut reservation) = directory.reserve("clip.mp4").unwrap();
    reservation
        .upgrade("task".into(), "attempt".into())
        .unwrap();
    file.write_all(b"original").unwrap();
    file.flush().unwrap();
    let checkpoint = reservation
        .checkpoint(8, Some(100), Some("\"stable\"".into()))
        .unwrap();
    drop(file);
    reservation.retain();
    let path = root.path().join(format!(".sctv-dl-{}.part", checkpoint.id));
    std::fs::OpenOptions::new()
        .write(true)
        .open(&path)
        .unwrap()
        .set_len(2)
        .unwrap();
    assert!(directory.recover_reservation(&checkpoint).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), b"or");
    #[cfg(unix)]
    {
        std::fs::remove_file(&path).unwrap();
        let target = root.path().join("outside");
        std::fs::write(&target, b"preserve").unwrap();
        std::os::unix::fs::symlink(&target, &path).unwrap();
        assert!(directory.recover_reservation(&checkpoint).is_err());
        assert_eq!(std::fs::read(&target).unwrap(), b"preserve");
    }
}

#[tokio::test]
async fn publication_crashes_reconcile_without_redownload_or_clobber() {
    use sctv_dl_desktop_lib::{
        downloads::{
            ContentRef, DownloadManager, DownloadTask, TaskState,
            store::{DownloadDocument, DownloadStore, StoredTask},
        },
        history::HistoryMetadata,
        media::Quality,
    };
    for published in [false, true] {
        let root = tempfile::tempdir().unwrap();
        let target = root.path().join("files");
        std::fs::create_dir(&target).unwrap();
        let directory = DownloadDirectory::open(&target).unwrap();
        let task_id = uuid::Uuid::new_v4().to_string();
        let attempt_id = uuid::Uuid::new_v4().to_string();
        let (mut file, mut reservation) = directory.reserve("clip.mp4").unwrap();
        reservation
            .upgrade(task_id.clone(), attempt_id.clone())
            .unwrap();
        file.write_all(b"complete").unwrap();
        file.flush().unwrap();
        drop(file);
        reservation
            .checkpoint(8, Some(8), Some("\"stable\"".into()))
            .unwrap();
        let publication = reservation.publication_intent().unwrap();
        let content = ContentRef {
            programme_id: "1".into(),
            date_id: "2".into(),
            content_id: "3".into(),
        };
        let record = StoredTask {
            task: DownloadTask {
                id: task_id.clone(),
                attempt_id,
                content: content.clone(),
                metadata: HistoryMetadata {
                    content,
                    programme_name: "News".into(),
                    broadcast_date: "2026-10-17".into(),
                    title: "Clip".into(),
                    cover: None,
                },
                filename: publication.filename.clone(),
                quality: Quality::Standard,
                state: TaskState::Finalizing,
                received_bytes: 8,
                total_bytes: Some(8),
                error: None,
                revision: 4,
                created_at: "2026-10-17T00:00:00.000Z".into(),
                can_resume: true,
                file_available: false,
                has_partial: true,
            },
            directory: target.canonicalize().unwrap(),
            reservation: Some(publication.clone()),
            completed_identity: None,
        };
        let index = root.path().join("downloads-v1.json");
        let store = DownloadStore::open(index.clone()).unwrap();
        store
            .save(&DownloadDocument {
                version: 1,
                revision: 9,
                tasks: vec![record],
            })
            .unwrap();
        if published {
            reservation.publish().unwrap();
        }
        reservation.retain();
        drop(directory);
        drop(store);
        let manager = DownloadManager::open(Default::default(), index)
            .await
            .unwrap();
        let task = manager.list()[0].clone();
        assert_eq!(task.id, task_id);
        if published {
            assert_eq!(task.state, TaskState::Completed);
            assert_eq!(
                std::fs::read(target.join(task.filename)).unwrap(),
                b"complete"
            );
            assert!(
                !target
                    .join(format!(".sctv-dl-{}.json", publication.id))
                    .exists()
            );
        } else {
            assert_eq!(task.state, TaskState::Interrupted);
            assert_eq!(task.received_bytes, 8);
            assert!(task.has_partial);
            assert!(!target.join(task.filename).exists());
        }
        manager.shutdown().await;
    }
}
