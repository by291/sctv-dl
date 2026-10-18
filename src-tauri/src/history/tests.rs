use std::time::Duration;

use super::*;
use crate::{downloads::DownloadManager, lifecycle::ExitController};

#[tokio::test(flavor = "current_thread")]
async fn dropped_mutations_keep_exit_waiting_and_do_not_block_snapshot_reads() {
    for mutation in ["begin", "record", "end", "remove", "clear"] {
        let root = tempfile::tempdir().unwrap();
        let service = HistoryService::open(root.path().join("history-v1.json")).await;
        let gate = Arc::new(ExitController::default());
        let metadata = HistoryMetadata {
            content: ContentRef {
                programme_id: "1".into(),
                date_id: "2".into(),
                content_id: "3".into(),
            },
            programme_name: "News".into(),
            broadcast_date: "2026-10-17".into(),
            title: "Evening".into(),
            cover: None,
        };
        let session = service
            .begin(metadata.clone(), gate.enter_save().await.unwrap())
            .await
            .unwrap();
        let owner = service.0.clone();
        let (locked, ready) = std::sync::mpsc::channel();
        let (release, wait) = std::sync::mpsc::channel();
        let blocker = std::thread::spawn(move || {
            let _writer = owner.writes.lock().unwrap();
            locked.send(()).unwrap();
            wait.recv_timeout(Duration::from_secs(5)).unwrap();
        });
        ready.recv().unwrap();

        let guard = gate.enter_save().await.unwrap();
        let future: std::pin::Pin<Box<dyn std::future::Future<Output = Result<()>>>> =
            match mutation {
                "begin" => {
                    Box::pin(async { service.begin(metadata.clone(), guard).await.map(|_| ()) })
                }
                "record" => Box::pin(async {
                    service
                        .record(
                            session.id,
                            HistorySample {
                                position_ms: 1,
                                duration_ms: None,
                                ended: false,
                                sequence: 1,
                            },
                            guard,
                        )
                        .await
                        .map(|_| ())
                }),
                "end" => Box::pin(service.end(session.id, guard)),
                "remove" => Box::pin(service.remove(metadata.content, guard)),
                _ => Box::pin(service.clear(guard)),
            };
        let mut future = future;
        assert!(futures_util::poll!(future.as_mut()).is_pending());
        drop(future);

        // The snapshot uses only the short state mutex, never the blocked writer.
        assert!(service.list().persisted);
        let downloads = DownloadManager::new(Default::default()).unwrap();
        let request = gate.begin().unwrap();
        let mut completion = Box::pin(request.complete(&downloads, || async { false }));
        let waited = tokio::time::timeout(Duration::from_millis(20), completion.as_mut())
            .await
            .is_err();

        release.send(()).unwrap();
        blocker.join().unwrap();
        assert!(completion.await);
        assert!(
            waited,
            "{mutation} released exit admission before its worker finished"
        );
    }
}
