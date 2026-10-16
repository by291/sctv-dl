use sctv_dl_desktop_lib::{
    error::{AppError, ErrorCode},
    requests::RequestRegistry,
};
use std::{sync::Arc, time::Duration};
use uuid::Uuid;

#[tokio::test(start_paused = true)]
async fn early_cancellation_expires_and_consumed_markers_do_not_poison_reuse() {
    let registry = Arc::new(RequestRegistry::default());
    let id = Uuid::new_v4().to_string();
    registry.cancel(&id).unwrap();
    let mut executed = false;
    let result = registry
        .register(&id)
        .unwrap()
        .run(async {
            executed = true;
            Ok(())
        })
        .await;
    assert_eq!(result.unwrap_err().code, ErrorCode::Cancelled);
    assert!(!executed);
    registry
        .register(&id)
        .unwrap()
        .run(async { Ok(()) })
        .await
        .unwrap();
    registry.cancel(&id).unwrap();
    tokio::time::advance(Duration::from_secs(60)).await;
    registry
        .register(&id)
        .unwrap()
        .run(async { Ok(()) })
        .await
        .unwrap();
}

#[tokio::test(start_paused = true)]
async fn early_cancellation_is_bounded_to_the_newest_1024_unique_requests() {
    let registry = Arc::new(RequestRegistry::default());
    let ids: Vec<_> = (0..1025).map(|_| Uuid::new_v4().to_string()).collect();
    for id in &ids {
        registry.cancel(id).unwrap();
    }
    registry
        .register(&ids[0])
        .unwrap()
        .run(async { Ok(()) })
        .await
        .unwrap();
    assert_eq!(
        registry
            .register(&ids[1])
            .unwrap()
            .run(async { Ok(()) })
            .await
            .unwrap_err()
            .code,
        ErrorCode::Cancelled
    );
    assert_eq!(
        registry
            .register(ids.last().unwrap())
            .unwrap()
            .run(async { Ok(()) })
            .await
            .unwrap_err()
            .code,
        ErrorCode::Cancelled
    );
}

#[tokio::test]
async fn validates_request_ids_rejects_duplicates_and_cleans_up_on_drop_or_failure() {
    let registry = Arc::new(RequestRegistry::default());
    assert!(registry.register("not-a-uuid").is_err());
    assert!(registry.cancel("not-a-uuid").is_err());
    assert!(
        registry
            .register("00000000-0000-4000-0000-000000000000")
            .is_err()
    );
    let id = Uuid::new_v4().to_string();
    let guard = registry.register(&id).unwrap();
    assert!(registry.register(&id).is_err());
    drop(guard);
    registry
        .register(&id)
        .unwrap()
        .run(async { Err::<(), _>(AppError::new(ErrorCode::Upstream, "Failure")) })
        .await
        .unwrap_err();
    registry
        .register(&id)
        .unwrap()
        .run(async { Ok(()) })
        .await
        .unwrap();
}
