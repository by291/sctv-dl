use std::sync::Arc;

use sctv_dl_desktop_lib::{
    lifecycle::ExitController,
    programme_cache::{BrowseState, CacheKey, CachePayload, ProgrammeCacheService},
};
use serde_json::json;

#[tokio::test]
async fn persists_empty_revisions_browse_and_fences_cleared_writes() {
    let root = tempfile::tempdir().unwrap();
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(root.path().join("cache")).await;
    let key = CacheKey::Catalogue;
    let initial = cache
        .read(key.clone(), lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert!(initial.snapshot.is_none());

    let payload: CachePayload =
        serde_json::from_value(json!({"kind":"catalogue", "items":[]})).unwrap();
    let first = cache
        .write(
            payload.clone(),
            initial.epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    let second = cache
        .write(
            payload.clone(),
            initial.epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(first.persisted);
    assert_eq!(
        first.snapshot.unwrap().revision,
        second.snapshot.unwrap().revision
    );

    let fixture: serde_json::Value =
        serde_json::from_str(include_str!("../../shared/fixtures/programme-cache.json")).unwrap();
    let shared_snapshot: sctv_dl_desktop_lib::programme_cache::Snapshot =
        serde_json::from_value(fixture["snapshot"].clone()).unwrap();
    shared_snapshot.validate().unwrap();
    let browse: BrowseState = serde_json::from_value(fixture["browse"].clone()).unwrap();

    cache
        .write_browse(
            browse,
            initial.epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(
        cache
            .read_browse("1".into(), lifecycle.enter_save().await.unwrap())
            .await
            .unwrap()
            .value
            .is_some()
    );

    let clear = cache
        .clear(lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert_ne!(clear.epoch, initial.epoch);
    assert!(
        !cache
            .write(
                payload.clone(),
                initial.epoch,
                lifecycle.enter_save().await.unwrap()
            )
            .await
            .unwrap()
            .accepted
    );

    assert!(
        cache
            .write(payload, clear.epoch, lifecycle.enter_save().await.unwrap())
            .await
            .unwrap()
            .persisted
    );

    drop(cache);

    let reopened = ProgrammeCacheService::open(root.path().join("cache")).await;
    assert!(
        reopened
            .read(key, lifecycle.enter_save().await.unwrap())
            .await
            .unwrap()
            .snapshot
            .is_some()
    );

    assert!(
        reopened
            .read_browse("1".into(), lifecycle.enter_save().await.unwrap())
            .await
            .unwrap()
            .value
            .is_none()
    );
}

#[tokio::test]
async fn evicts_lru_and_limits_browse_without_touching_other_data() {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("history.json"), "preserved").unwrap();
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(root.path().join("cache")).await;
    let epoch = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap()
        .epoch;

    for id in 0..200 {
        let payload = serde_json::from_value(json!({
            "kind": "dates",
            "programmeId": id.to_string(),
            "items": []
        }))
        .unwrap();
        cache
            .write(
                payload,
                epoch.clone(),
                lifecycle.enter_save().await.unwrap(),
            )
            .await
            .unwrap();
    }

    cache
        .read(
            CacheKey::Dates {
                programme_id: "0".into(),
            },
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    cache
        .write(
            serde_json::from_value(json!({
                "kind": "dates",
                "programmeId": "200",
                "items": []
            }))
            .unwrap(),
            epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(
        cache
            .read(
                CacheKey::Dates {
                    programme_id: "1".into()
                },
                lifecycle.enter_save().await.unwrap()
            )
            .await
            .unwrap()
            .snapshot
            .is_none()
    );

    for id in 0..101 {
        let value = serde_json::from_value(json!({
            "programmeId": id.to_string(),
            "dateId": null,
            "date": null,
            "sort": "asc",
            "scrollY": id,
            "visitedAt": format!("2026-10-17T00:{:02}:{:02}.000Z", id / 60, id % 60),
        }))
        .unwrap();
        cache
            .write_browse(value, epoch.clone(), lifecycle.enter_save().await.unwrap())
            .await
            .unwrap();
    }
    assert!(
        cache
            .read_browse("0".into(), lifecycle.enter_save().await.unwrap())
            .await
            .unwrap()
            .value
            .is_none()
    );

    cache
        .clear(lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert_eq!(
        std::fs::read_to_string(root.path().join("history.json")).unwrap(),
        "preserved"
    );
}

#[tokio::test]
async fn corruption_is_local_and_corrupt_manifest_never_rediscovers_old_epochs() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("cache");
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(path.clone()).await;
    let epoch = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap()
        .epoch;
    cache
        .write(
            serde_json::from_value(json!({"kind":"catalogue","items":[]})).unwrap(),
            epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    let manifest: serde_json::Value =
        serde_json::from_slice(&std::fs::read(path.join("manifest.json")).unwrap()).unwrap();
    let file = manifest["entries"]["catalogue"]["file"].as_str().unwrap();
    std::fs::write(path.join(&epoch).join(file), "broken").unwrap();

    let corrupt = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert!(corrupt.snapshot.is_none());
    assert!(corrupt.warning.is_some());

    assert!(
        cache
            .write(
                serde_json::from_value(json!({"kind":"catalogue","items":[]})).unwrap(),
                epoch.clone(),
                lifecycle.enter_save().await.unwrap()
            )
            .await
            .unwrap()
            .persisted
    );

    drop(cache);
    std::fs::write(path.join("manifest.json"), "corrupt index").unwrap();
    let cache = ProgrammeCacheService::open(path).await;
    let recovered = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert_ne!(recovered.epoch, epoch);
    assert!(recovered.snapshot.is_none());
    assert!(recovered.warning.is_some());
}

#[tokio::test]
async fn oversized_multibyte_snapshot_preserves_committed_data_and_total_bytes_evict() {
    let root = tempfile::tempdir().unwrap();
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(root.path().join("cache")).await;
    let epoch = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap()
        .epoch;
    cache
        .write(
            serde_json::from_value(json!({"kind":"catalogue","items":[]})).unwrap(),
            epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    let oversized = cache
        .write(
            serde_json::from_value(json!({
                "kind": "catalogue",
                "items": [{ "id": "1", "name": "川".repeat(7_000_000) }]
            }))
            .unwrap(),
            epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(oversized.accepted);
    assert!(!oversized.persisted);
    let previous = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert_eq!(
        serde_json::to_value(previous.snapshot.unwrap()).unwrap()["items"],
        json!([])
    );

    for id in 0..3 {
        let payload = serde_json::from_value(json!({
            "kind": "contents",
            "programmeId": "1",
            "dateId": id.to_string(),
            "items": [{ "id": "1", "title": "川".repeat(2_400_000) }],
        }))
        .unwrap();
        assert!(
            cache
                .write(
                    payload,
                    epoch.clone(),
                    lifecycle.enter_save().await.unwrap()
                )
                .await
                .unwrap()
                .persisted
        );
    }
    assert!(
        cache
            .read(
                CacheKey::Contents {
                    programme_id: "1".into(),
                    date_id: "0".into()
                },
                lifecycle.enter_save().await.unwrap()
            )
            .await
            .unwrap()
            .snapshot
            .is_none()
    );
}

#[tokio::test]
async fn failed_write_keeps_the_previous_committed_snapshot_and_locked_owner_is_memory_only() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("cache");
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(path.clone()).await;
    let epoch = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap()
        .epoch;
    let original = cache
        .write(
            serde_json::from_value(json!({"kind":"catalogue","items":[]})).unwrap(),
            epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    let locked = ProgrammeCacheService::open(path.clone()).await;
    assert!(
        !locked
            .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
            .await
            .unwrap()
            .persisted
    );
    drop(locked);
    let committed = std::fs::read(path.join("manifest.json")).unwrap();
    std::fs::rename(path.join("manifest.json"), path.join("committed.json")).unwrap();
    std::fs::create_dir(path.join("manifest.json")).unwrap();
    let failed = cache
        .write(
            serde_json::from_value(json!({
                "kind": "catalogue",
                "items": [{ "id": "1", "name": "new" }]
            }))
            .unwrap(),
            epoch,
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(failed.accepted);
    assert!(!failed.persisted);
    assert_eq!(
        std::fs::read(path.join("committed.json")).unwrap(),
        committed
    );

    std::fs::remove_dir(path.join("manifest.json")).unwrap();
    std::fs::rename(path.join("committed.json"), path.join("manifest.json")).unwrap();
    drop(cache);

    let reopened = ProgrammeCacheService::open(path).await;
    let restored = reopened
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert_eq!(
        restored.snapshot.unwrap().revision,
        original.snapshot.unwrap().revision
    );
}

fn empty_dates(id: &str) -> CachePayload {
    CachePayload::Dates {
        programme_id: id.into(),
        items: Vec::new(),
    }
}

#[tokio::test]
async fn rejected_stale_epoch_reports_memory_only_snapshot() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("cache");
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(path.clone()).await;
    let epoch = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap()
        .epoch;

    std::fs::remove_file(path.join("manifest.json")).unwrap();
    std::fs::create_dir(path.join("manifest.json")).unwrap();
    let failed = cache
        .write(
            empty_dates("1"),
            epoch,
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(!failed.persisted);

    let rejected = cache
        .write(
            empty_dates("1"),
            "stale epoch".into(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(!rejected.accepted);
    assert!(rejected.snapshot.is_some());
    assert!(!rejected.persisted);
}

#[tokio::test]
async fn successful_retry_clears_persistence_warning() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("cache");
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(path.clone()).await;
    let epoch = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap()
        .epoch;

    std::fs::remove_file(path.join("manifest.json")).unwrap();
    std::fs::create_dir(path.join("manifest.json")).unwrap();
    let failed = cache
        .write(
            empty_dates("1"),
            epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(!failed.persisted);
    assert!(failed.warning.is_some());
    std::fs::remove_dir(path.join("manifest.json")).unwrap();

    let recovered = cache
        .write(
            empty_dates("1"),
            epoch,
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(recovered.persisted);
    assert!(recovered.warning.is_none());

    let browse = cache
        .read_browse("1".into(), lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert!(browse.persisted);
    assert!(browse.warning.is_none());
}

#[cfg(unix)]
#[tokio::test]
async fn replaced_manifest_survives_sync_failure_and_unrelated_read() {
    use std::os::unix::fs::PermissionsExt;

    struct RestorePermissions(std::path::PathBuf, std::fs::Permissions);

    impl Drop for RestorePermissions {
        fn drop(&mut self) {
            std::fs::set_permissions(&self.0, self.1.clone()).unwrap();
        }
    }

    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("cache");
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(path.clone()).await;
    let epoch = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap()
        .epoch;
    cache
        .write(
            empty_dates("1"),
            epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    // Search/write permission permits replacement; opening the parent for its
    // durability barrier fails without read permission. Restore before recovery.
    let permissions = RestorePermissions(
        path.clone(),
        std::fs::metadata(&path).unwrap().permissions(),
    );

    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o300)).unwrap();

    if std::fs::File::open(&path).is_ok() {
        // Privileged runners may bypass directory permissions, as in the history
        // sync-failure tests. They cannot exercise this filesystem failure mode.
        drop(permissions);
        return;
    }

    let failed = cache
        .write(
            empty_dates("2"),
            epoch,
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    drop(permissions);

    assert!(!failed.persisted);

    let recovered = cache
        .read(
            CacheKey::Dates {
                programme_id: "1".into(),
            },
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(recovered.persisted);
    assert!(recovered.warning.is_none());
    drop(cache);

    let reopened = ProgrammeCacheService::open(path).await;
    let retained = reopened
        .read(
            CacheKey::Dates {
                programme_id: "2".into(),
            },
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(retained.snapshot.is_some());
    assert!(retained.persisted);
}

#[cfg(unix)]
struct RestoreFilePermissions(std::path::PathBuf, std::fs::Permissions);

#[cfg(unix)]
impl RestoreFilePermissions {
    fn unreadable(path: std::path::PathBuf) -> Self {
        use std::os::unix::fs::PermissionsExt;

        let permissions = std::fs::metadata(&path).unwrap().permissions();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o000)).unwrap();

        Self(path, permissions)
    }

    fn enforced(&self) -> bool {
        std::fs::File::open(&self.0).is_err()
    }
}

#[cfg(unix)]
impl Drop for RestoreFilePermissions {
    fn drop(&mut self) {
        std::fs::set_permissions(&self.0, self.1.clone()).unwrap();
    }
}

#[cfg(unix)]
#[tokio::test]
async fn unreadable_manifest_is_preserved_until_reopen() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("cache");
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(path.clone()).await;
    let epoch = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap()
        .epoch;
    let original = cache
        .write(
            empty_dates("1"),
            epoch,
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap()
        .snapshot
        .unwrap();
    drop(cache);
    let committed = std::fs::read(path.join("manifest.json")).unwrap();
    let permissions = RestoreFilePermissions::unreadable(path.join("manifest.json"));

    if !permissions.enforced() {
        return;
    }

    let unavailable = ProgrammeCacheService::open(path.clone()).await;
    let current = unavailable
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert!(!current.persisted);
    assert!(current.warning.is_some());
    drop(permissions);
    assert_eq!(
        std::fs::read(path.join("manifest.json")).unwrap(),
        committed
    );

    let memory_only = unavailable
        .write(
            empty_dates("2"),
            current.epoch,
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(!memory_only.persisted);
    assert!(
        unavailable
            .clear(lifecycle.enter_save().await.unwrap())
            .await
            .is_err()
    );
    assert_eq!(
        std::fs::read(path.join("manifest.json")).unwrap(),
        committed
    );

    let second_owner = ProgrammeCacheService::open(path.clone()).await;
    let locked = second_owner
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert!(!locked.persisted);
    drop(second_owner);
    drop(unavailable);

    let reopened = ProgrammeCacheService::open(path).await;
    let retained = reopened
        .read(
            CacheKey::Dates {
                programme_id: "1".into(),
            },
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(retained.persisted);
    assert_eq!(retained.snapshot.unwrap().revision, original.revision);
}

#[cfg(unix)]
#[tokio::test]
async fn unreadable_snapshot_reports_failure_and_can_retry_without_refetching() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("cache");
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(path.clone()).await;
    let epoch = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap()
        .epoch;
    let original = cache
        .write(
            empty_dates("1"),
            epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap()
        .snapshot
        .unwrap();
    let manifest: serde_json::Value =
        serde_json::from_slice(&std::fs::read(path.join("manifest.json")).unwrap()).unwrap();
    let file = manifest["entries"]["dates:1"]["file"].as_str().unwrap();
    let permissions = RestoreFilePermissions::unreadable(path.join(epoch).join(file));

    if !permissions.enforced() {
        return;
    }

    let key = CacheKey::Dates {
        programme_id: "1".into(),
    };
    let failed = cache
        .read(key.clone(), lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert!(failed.snapshot.is_none());
    assert!(failed.warning.is_some());
    assert!(!failed.persisted);

    let rejected = cache
        .write(
            empty_dates("1"),
            "stale epoch".into(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(!rejected.accepted);
    assert!(!rejected.persisted);
    assert!(rejected.snapshot.is_none());
    drop(permissions);

    let recovered = cache
        .read(key, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert!(recovered.persisted);
    assert!(recovered.warning.is_none());
    assert_eq!(recovered.snapshot.unwrap().revision, original.revision);
}

fn browse_state(scroll_y: f64) -> BrowseState {
    BrowseState {
        programme_id: "1".into(),
        date_id: None,
        date: None,
        sort: "asc".into(),
        scroll_y,
        visited_at: "2026-10-18T00:00:00.000Z".into(),
    }
}

#[cfg(unix)]
#[tokio::test]
async fn unchanged_candidates_preserve_saved_browse_durability() {
    use std::os::unix::fs::PermissionsExt;

    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("cache");
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(path.clone()).await;
    let epoch = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap()
        .epoch;
    let saved = cache
        .write_browse(
            browse_state(10.0),
            epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(saved.persisted);
    let committed = std::fs::read(path.join("manifest.json")).unwrap();
    let directory = path.join(&epoch);
    std::fs::create_dir(&directory).unwrap();
    let permissions = RestoreFilePermissions(
        directory.clone(),
        std::fs::metadata(&directory).unwrap().permissions(),
    );
    std::fs::set_permissions(&directory, std::fs::Permissions::from_mode(0o500)).unwrap();

    if tempfile::NamedTempFile::new_in(&directory).is_ok() {
        return;
    }

    let failed = cache
        .write(
            empty_dates("1"),
            epoch,
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert!(!failed.persisted);
    assert!(failed.warning.is_some());
    assert_eq!(
        std::fs::read(path.join("manifest.json")).unwrap(),
        committed
    );

    let browse = cache
        .read_browse("1".into(), lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();
    let rejected = cache
        .write_browse(
            browse_state(20.0),
            "stale epoch".into(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(browse.value.unwrap().scroll_y, 10.0);
    assert!(browse.persisted);
    assert!(browse.warning.is_some());
    assert!(!rejected.accepted);
    assert!(rejected.persisted);
    drop(permissions);

    std::fs::rename(path.join("manifest.json"), path.join("committed.json")).unwrap();
    std::fs::create_dir(path.join("manifest.json")).unwrap();
    assert!(
        cache
            .clear(lifecycle.enter_save().await.unwrap())
            .await
            .is_err()
    );
    let retained = cache
        .read_browse("1".into(), lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert!(retained.persisted);
    assert_eq!(retained.value.unwrap().scroll_y, 10.0);
}

#[tokio::test]
async fn unchanged_browse_failure_stays_memory_only_until_full_index_commit() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("cache");
    let lifecycle = Arc::new(ExitController::default());
    let cache = ProgrammeCacheService::open(path.clone()).await;
    let epoch = cache
        .read(CacheKey::Catalogue, lifecycle.enter_save().await.unwrap())
        .await
        .unwrap()
        .epoch;
    cache
        .write_browse(
            browse_state(10.0),
            epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();

    std::fs::rename(path.join("manifest.json"), path.join("committed.json")).unwrap();
    std::fs::create_dir(path.join("manifest.json")).unwrap();
    let failed = cache
        .write_browse(
            browse_state(20.0),
            epoch.clone(),
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    let pending = cache
        .read_browse("1".into(), lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert!(!failed.persisted);
    assert!(!pending.persisted);
    assert_eq!(pending.value.unwrap().scroll_y, 20.0);
    std::fs::remove_dir(path.join("manifest.json")).unwrap();
    std::fs::rename(path.join("committed.json"), path.join("manifest.json")).unwrap();

    let recovered = cache
        .write(
            empty_dates("1"),
            epoch,
            lifecycle.enter_save().await.unwrap(),
        )
        .await
        .unwrap();
    let saved = cache
        .read_browse("1".into(), lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert!(recovered.persisted);
    assert!(saved.persisted);
    assert_eq!(saved.value.unwrap().scroll_y, 20.0);
    drop(cache);

    let reopened = ProgrammeCacheService::open(path).await;
    let durable = reopened
        .read_browse("1".into(), lifecycle.enter_save().await.unwrap())
        .await
        .unwrap();

    assert!(durable.persisted);
    assert_eq!(durable.value.unwrap().scroll_y, 20.0);
}
