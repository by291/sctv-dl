use sctv_dl_desktop_lib::{
    lifecycle::ExitController,
    programme_cache::{BrowseState, CacheKey, CachePayload, ProgrammeCacheService},
};
use serde_json::json;
use std::sync::Arc;

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
        let payload = serde_json::from_value(
            json!({"kind":"dates", "programmeId":id.to_string(), "items":[]}),
        )
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
            serde_json::from_value(json!({"kind":"dates", "programmeId":"200", "items":[]}))
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
        let value = serde_json::from_value(json!({"programmeId":id.to_string(),"dateId":null,"date":null,"sort":"asc","scrollY":id,"visitedAt":format!("2026-10-17T00:{:02}:{:02}.000Z",id/60,id%60)})).unwrap();
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
            serde_json::from_value(
                json!({"kind":"catalogue","items":[{"id":"1","name":"川".repeat(7_000_000)}]}),
            )
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
        let payload = serde_json::from_value(json!({"kind":"contents","programmeId":"1","dateId":id.to_string(),"items":[{"id":"1","title":"川".repeat(2_400_000)}]})).unwrap();
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
            serde_json::from_value(json!({"kind":"catalogue","items":[{"id":"1","name":"new"}]}))
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
