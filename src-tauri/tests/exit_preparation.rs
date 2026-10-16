use sctv_dl_desktop_lib::lifecycle::ExitPreparation;
use std::{sync::Arc, time::Duration};

#[tokio::test]
async fn preparation_checks_tokens_and_handles_missing_or_unresponsive_frontends() {
    let preparation = Arc::new(ExitPreparation::default());
    assert!(preparation.prepare(Duration::from_millis(10)).await);
    let (send, mut receive) = tokio::sync::mpsc::unbounded_channel();
    let subscription = preparation.subscribe(move |id| send.send(id).is_ok());
    let pending = {
        let preparation = preparation.clone();
        tokio::spawn(async move { preparation.prepare(Duration::from_secs(1)).await })
    };
    let request = receive.recv().await.unwrap();
    preparation.complete("wrong-token", true);
    assert!(!pending.is_finished());
    preparation.complete(&request, false);
    assert!(!pending.await.unwrap());
    assert!(!preparation.prepare(Duration::from_millis(10)).await);
    preparation.unsubscribe("wrong-subscription");
    assert!(!preparation.prepare(Duration::from_millis(10)).await);
    preparation.unsubscribe(&subscription);
    assert!(preparation.prepare(Duration::from_millis(10)).await);
}
