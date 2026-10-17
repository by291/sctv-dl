use sctv_dl_desktop_lib::{history::*, lifecycle::ExitController};
use serde_json::json;

fn metadata(id: &str) -> HistoryMetadata {
    serde_json::from_value(json!({"content":{"programmeId":"1","dateId":"2","contentId":id},"programmeName":"News","broadcastDate":"2026-10-17","title":"Evening","cover":null})).unwrap()
}
fn sample(position_ms: u64, sequence: u64) -> HistorySample {
    HistorySample {
        position_ms,
        duration_ms: Some(100_000),
        ended: false,
        sequence,
    }
}

#[cfg(unix)]
#[tokio::test]
async fn replacement_sync_failure_keeps_deleted_tokens_invalidated() {
    use std::{fs, os::unix::fs::PermissionsExt};

    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("history-v1.json");
    let gate = ExitController::default();
    let service = HistoryService::open(path.clone()).await;
    let session = service
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    service
        .record(
            session.id.clone(),
            sample(30_000, 1),
            gate.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    // Write/execute allows temporary-file creation and rename, but prevents
    // opening the directory for the synchronization after replacement.
    fs::set_permissions(root.path(), fs::Permissions::from_mode(0o300)).unwrap();
    if fs::File::open(root.path()).is_ok() {
        // Privileged Unix runners bypass permission bits; this fault requires
        // an ordinary user. The current host exercises the path below.
        fs::set_permissions(root.path(), fs::Permissions::from_mode(0o700)).unwrap();
        return;
    }
    let removal = service
        .remove(metadata("3").content, gate.enter_save().await.unwrap())
        .await;
    fs::set_permissions(root.path(), fs::Permissions::from_mode(0o700)).unwrap();

    assert!(removal.is_err());
    let disk: serde_json::Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert_eq!(disk["entries"], json!([]));
    let snapshot = service.list();
    assert!(!snapshot.persisted);
    assert!(snapshot.warning.is_some());
    assert!(snapshot.entries.is_empty());
    assert!(
        !service
            .record(
                session.id,
                sample(40_000, 2),
                gate.enter_save().await.unwrap()
            )
            .await
            .unwrap()
            .accepted
    );
    service
        .clear(gate.enter_save().await.unwrap())
        .await
        .unwrap();
    assert!(service.list().persisted);
}

#[cfg(unix)]
#[tokio::test]
async fn retries_durability_for_an_already_replaced_sample() {
    use std::{fs, os::unix::fs::PermissionsExt};

    let root = tempfile::tempdir().unwrap();
    let service = HistoryService::open(root.path().join("history-v1.json")).await;
    let gate = ExitController::default();
    let session = service
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    fs::set_permissions(root.path(), fs::Permissions::from_mode(0o300)).unwrap();
    if fs::File::open(root.path()).is_ok() {
        fs::set_permissions(root.path(), fs::Permissions::from_mode(0o700)).unwrap();
        return;
    }
    let record = service
        .record(
            session.id.clone(),
            sample(30_000, 1),
            gate.enter_save().await.unwrap(),
        )
        .await;
    fs::set_permissions(root.path(), fs::Permissions::from_mode(0o700)).unwrap();
    assert!(record.is_err());
    assert_eq!(service.list().entries[0].position_ms, 30_000);
    assert!(!service.list().persisted);

    let retry = service
        .record(
            session.id,
            sample(30_000, 1),
            gate.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    assert!(retry.persisted);
    assert!(!retry.accepted);
    assert_eq!(service.list().entries[0].position_ms, 30_000);
}

#[tokio::test]
async fn saves_reload_without_tokens_and_failed_preparation_preserves_progress() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("history-v1.json");
    let gate = ExitController::default();
    let service = HistoryService::open(path.clone()).await;
    let session = service
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    service
        .record(
            session.id.clone(),
            sample(30_000, 1),
            gate.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    let reopened = service
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    assert_eq!(reopened.entry.unwrap().position_ms, 30_000);
    drop(service);
    let service = HistoryService::open(path).await;
    assert_eq!(service.list().entries[0].position_ms, 30_000);
    assert!(
        !service
            .record(
                session.id,
                sample(90_000, 2),
                gate.enter_save().await.unwrap()
            )
            .await
            .unwrap()
            .accepted
    );
}

#[tokio::test]
async fn newest_session_and_sequence_win_and_deletions_cannot_be_resurrected() {
    let root = tempfile::tempdir().unwrap();
    let service = HistoryService::open(root.path().join("history-v1.json")).await;
    let gate = ExitController::default();
    let old = service
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    let new = service
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    assert!(
        !service
            .record(old.id, sample(90_000, 8), gate.enter_save().await.unwrap())
            .await
            .unwrap()
            .accepted
    );
    assert!(
        service
            .record(
                new.id.clone(),
                sample(95_000, 2),
                gate.enter_save().await.unwrap()
            )
            .await
            .unwrap()
            .accepted
    );
    assert!(service.list().entries[0].completed);
    assert!(
        !service
            .record(
                new.id.clone(),
                sample(10_000, 1),
                gate.enter_save().await.unwrap()
            )
            .await
            .unwrap()
            .accepted
    );
    service
        .record(
            new.id.clone(),
            sample(10_000, 3),
            gate.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    assert!(!service.list().entries[0].completed);
    service
        .remove(metadata("3").content, gate.enter_save().await.unwrap())
        .await
        .unwrap();
    assert!(
        !service
            .record(new.id, sample(50_000, 4), gate.enter_save().await.unwrap())
            .await
            .unwrap()
            .accepted
    );
    let next = service
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    service
        .clear(gate.enter_save().await.unwrap())
        .await
        .unwrap();
    assert!(
        !service
            .record(next.id, sample(50_000, 1), gate.enter_save().await.unwrap())
            .await
            .unwrap()
            .accepted
    );
    assert!(service.list().entries.is_empty());
}

#[tokio::test]
async fn corrupt_documents_are_preserved_and_second_owner_never_overwrites() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("history-v1.json");
    std::fs::write(&path, b"{broken").unwrap();
    let gate = ExitController::default();
    let service = HistoryService::open(path.clone()).await;
    assert!(!service.list().persisted);
    assert!(service.list().warning.is_some());
    let session = service
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    assert!(
        !service
            .record(session.id, sample(5, 1), gate.enter_save().await.unwrap())
            .await
            .unwrap()
            .persisted
    );
    assert_eq!(service.list().entries[0].position_ms, 5);
    assert_eq!(std::fs::read(&path).unwrap(), b"{broken");
    drop(service);
    std::fs::remove_file(&path).unwrap();
    let first = HistoryService::open(path.clone()).await;
    let second = HistoryService::open(path.clone()).await;
    assert!(first.list().persisted);
    assert!(!second.list().persisted);
    assert!(second.list().warning.is_some());
    let session = second
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    second
        .record(session.id, sample(5, 1), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    assert!(!path.exists());
}

#[tokio::test]
async fn failed_replacement_rolls_back_entries_and_sequence_for_retry() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("history-v1.json");
    let service = HistoryService::open(path.clone()).await;
    let gate = ExitController::default();
    let session = service
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    service
        .record(
            session.id.clone(),
            sample(100, 1),
            gate.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    let bytes = std::fs::read(&path).unwrap();
    std::fs::remove_file(&path).unwrap();
    std::fs::create_dir(&path).unwrap();
    assert!(
        service
            .record(
                session.id.clone(),
                sample(200, 2),
                gate.enter_save().await.unwrap()
            )
            .await
            .is_err()
    );
    assert_eq!(service.list().entries[0].position_ms, 100);
    assert!(!service.list().persisted);
    std::fs::remove_dir(&path).unwrap();
    std::fs::write(&path, bytes).unwrap();
    assert!(
        service
            .record(session.id, sample(200, 2), gate.enter_save().await.unwrap())
            .await
            .unwrap()
            .accepted
    );
    assert!(service.list().persisted);
}

#[tokio::test]
async fn retains_the_newest_500_entries() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("history-v1.json");
    // Session-only mode avoids making the boundary test depend on 501 disk syncs.
    std::fs::write(&path, b"broken").unwrap();
    let service = HistoryService::open(path).await;
    let gate = ExitController::default();
    for index in 0..501 {
        let session = service
            .begin(
                metadata(&index.to_string()),
                gate.enter_save().await.unwrap(),
            )
            .await
            .unwrap();
        service
            .record(
                session.id,
                sample(index, 1),
                gate.enter_save().await.unwrap(),
            )
            .await
            .unwrap();
    }
    let entries = service.list().entries;
    assert_eq!(entries.len(), 500);
    assert_eq!(entries[0].metadata.content.content_id, "500");
    assert_eq!(entries[499].metadata.content.content_id, "1");
}

#[tokio::test]
async fn invalid_metadata_and_samples_do_not_claim_sessions_or_change_progress() {
    let root = tempfile::tempdir().unwrap();
    let service = HistoryService::open(root.path().join("history-v1.json")).await;
    let gate = ExitController::default();
    let session = service
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    for invalid in [
        HistoryMetadata {
            title: "x".repeat(16 * 1024),
            ..metadata("3")
        },
        HistoryMetadata {
            broadcast_date: "2026-02-30".into(),
            ..metadata("3")
        },
        HistoryMetadata {
            cover: Some("file:///private/data".into()),
            ..metadata("3")
        },
        metadata("not-an-id"),
    ] {
        assert!(
            service
                .begin(invalid, gate.enter_save().await.unwrap())
                .await
                .is_err()
        );
    }
    for invalid in [sample(100, 0), sample(9_007_199_254_740_992, 1)] {
        assert!(
            service
                .record(
                    session.id.clone(),
                    invalid,
                    gate.enter_save().await.unwrap()
                )
                .await
                .is_err()
        );
    }
    assert!(service.list().entries.is_empty());
    assert!(
        service
            .record(session.id, sample(100, 1), gate.enter_save().await.unwrap())
            .await
            .unwrap()
            .accepted
    );
}

#[tokio::test]
async fn subscribers_observe_committed_snapshots_and_can_detach() {
    let root = tempfile::tempdir().unwrap();
    let service = HistoryService::open(root.path().join("history-v1.json")).await;
    let gate = ExitController::default();
    let snapshots = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
    let observed = snapshots.clone();
    let subscription = service.subscribe(move |snapshot| {
        observed.lock().unwrap().push(snapshot);
        true
    });
    let session = service
        .begin(metadata("3"), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    service
        .record(session.id, sample(100, 1), gate.enter_save().await.unwrap())
        .await
        .unwrap();
    service
        .clear(gate.enter_save().await.unwrap())
        .await
        .unwrap();
    {
        let snapshots = snapshots.lock().unwrap();
        assert_eq!(snapshots.len(), 2);
        assert_eq!(snapshots[0].entries[0].position_ms, 100);
        assert!(snapshots[1].entries.is_empty());
        assert!(snapshots[1].revision > snapshots[0].revision);
        assert!(snapshots.iter().all(|snapshot| snapshot.persisted));
    }
    service.unsubscribe(&subscription);
    service
        .clear(gate.enter_save().await.unwrap())
        .await
        .unwrap();
    assert_eq!(snapshots.lock().unwrap().len(), 2);
}

#[tokio::test]
async fn oversized_document_is_preserved_in_session_only_mode() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("history-v1.json");
    let bytes = vec![b' '; 8 * 1024 * 1024 + 1];
    std::fs::write(&path, &bytes).unwrap();
    let service = HistoryService::open(path.clone()).await;
    assert!(!service.list().persisted);
    assert!(service.list().warning.is_some());
    assert_eq!(std::fs::read(path).unwrap(), bytes);
}

#[test]
fn native_completion_matches_the_shared_fixture() {
    let fixture: serde_json::Value =
        serde_json::from_str(include_str!("../../shared/fixtures/history.json")).unwrap();
    for case in fixture["completion"].as_array().unwrap() {
        let sample = HistorySample {
            position_ms: case["positionMs"].as_u64().unwrap(),
            duration_ms: case["durationMs"].as_u64(),
            ended: case["ended"].as_bool().unwrap(),
            sequence: 1,
        };
        assert_eq!(
            sample.completed(),
            case["completed"].as_bool().unwrap(),
            "{case}"
        );
    }
}

#[tokio::test]
async fn metadata_uses_the_same_http_url_shape_as_the_shared_contract() {
    let root = tempfile::tempdir().unwrap();
    let service = HistoryService::open(root.path().join("history-v1.json")).await;
    let gate = ExitController::default();
    for cover in ["http:example.com", "HTTP://example.com"] {
        let metadata = HistoryMetadata {
            cover: Some(cover.into()),
            ..metadata("3")
        };
        assert!(
            service
                .begin(metadata, gate.enter_save().await.unwrap())
                .await
                .is_err()
        );
    }
}
