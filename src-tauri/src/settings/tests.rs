use super::*;
use std::{
    sync::atomic::{AtomicBool, Ordering},
    time::Duration,
};

#[tokio::test(flavor = "current_thread")]
async fn waiting_for_a_settings_write_keeps_the_async_runtime_responsive() {
    let settings = Arc::new(DesktopSettings::<tauri::test::MockRuntime>::new(Err(
        AppError::new(ErrorCode::Storage, "Unavailable test store"),
    )));
    let writes = settings.writes.clone();
    let timed_out = Arc::new(AtomicBool::new(false));
    let worker_timed_out = timed_out.clone();
    let (locked, ready) = std::sync::mpsc::channel();
    let (release, wait) = std::sync::mpsc::channel();
    let writer = std::thread::spawn(move || {
        let _write = writes.lock().unwrap();
        locked.send(()).unwrap();
        if wait.recv_timeout(Duration::from_secs(1)).is_err() {
            worker_timed_out.store(true, Ordering::SeqCst);
        }
    });
    ready.recv().unwrap();

    let mut read = Box::pin(settings.load());
    let first_poll = futures_util::poll!(read.as_mut());
    let responsive = first_poll.is_pending() && !timed_out.load(Ordering::SeqCst);
    let _ = release.send(());
    writer.join().unwrap();
    let snapshot = match first_poll {
        std::task::Poll::Pending => read.await,
        std::task::Poll::Ready(snapshot) => snapshot,
    };

    assert!(
        responsive,
        "the settings read blocked the async runtime waiting for its writer"
    );
    assert!(!snapshot.persisted);
}

#[tokio::test(flavor = "current_thread")]
async fn dropping_directory_persistence_keeps_exit_waiting_for_the_owned_worker() {
    use crate::{downloads::DownloadManager, lifecycle::ExitController};
    use tauri::test::{mock_builder, mock_context, noop_assets};
    use tauri_plugin_store::StoreExt;

    let root = tempfile::tempdir().unwrap();
    let destination = root.path().join("downloads");
    std::fs::create_dir(&destination).unwrap();
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .build(mock_context(noop_assets()))
        .unwrap();
    let store_path = root.path().join("desktop.json");
    let store = app
        .store_builder(&store_path)
        .disable_auto_save()
        .build()
        .unwrap();
    let settings = DesktopSettings::new(Ok(store));
    let controller = Arc::new(ExitController::default());
    let downloads = DownloadManager::new(Default::default()).unwrap();

    let writes = settings.writes.clone();
    let (locked, ready) = std::sync::mpsc::channel();
    let (release, wait) = std::sync::mpsc::channel();
    let writer = std::thread::spawn(move || {
        let _write = writes.lock().unwrap();
        locked.send(()).unwrap();
        let _ = wait.recv_timeout(Duration::from_secs(5));
    });
    ready.recv().unwrap();

    let operation = Arc::new(controller.enter().await.unwrap());
    let selection = settings.selection.clone().lock_owned().await;
    let mut persistence =
        Box::pin(settings.persist_directory(destination.clone(), operation, selection));
    assert!(futures_util::poll!(persistence.as_mut()).is_pending());
    drop(persistence);

    let request = controller.begin().unwrap();
    let mut completion = Box::pin(request.complete(&downloads, || async {
        panic!("there are no downloads to confirm")
    }));
    let observed_exit = tokio::time::timeout(Duration::from_millis(20), completion.as_mut()).await;
    let exit_waited = observed_exit.is_err() && !controller.committed();
    let picker_serialized = settings.selection.try_lock().is_err();

    release.send(()).unwrap();
    writer.join().unwrap();
    let exited = match observed_exit {
        Ok(exited) => exited,
        Err(_) => completion.await,
    };

    // Also settle the worker when checking a broken guard implementation so
    // assertion failure cannot race disposal of its temporary directory.
    let disk: serde_json::Value = tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            if let Ok(bytes) = tokio::fs::read(&store_path).await
                && let Ok(value) = serde_json::from_slice(&bytes)
            {
                break value;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert!(
        exit_waited,
        "exit committed before its persistence worker completed"
    );
    assert!(
        picker_serialized,
        "dropping persistence released picker serialization early"
    );
    assert!(exited);
    assert_eq!(
        disk["downloadDirectory"],
        destination.canonicalize().unwrap().to_str().unwrap()
    );
    assert!(settings.selection.try_lock().is_ok());
}
