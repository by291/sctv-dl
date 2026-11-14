use std::{sync::Arc, time::Duration};

use sctv_dl_desktop_lib::lifecycle::{ExitEvent, ExitPreparation};

const ACK_TIMEOUT: Duration = Duration::from_secs(1);
const SHORT_TIMEOUT: Duration = Duration::from_millis(10);

#[tokio::test]
async fn preparation_checks_tokens_and_handles_missing_or_unresponsive_frontends() {
    let preparation = Arc::new(ExitPreparation::default());
    assert!(preparation.attempt().prepare(SHORT_TIMEOUT).await);

    let (send, mut receive) = tokio::sync::mpsc::unbounded_channel();
    let subscription = preparation.subscribe(move |event| send.send(event).is_ok());
    let pending = {
        let preparation = preparation.clone();
        tokio::spawn(async move { preparation.attempt().prepare(ACK_TIMEOUT).await })
    };
    let Some(ExitEvent::Prepare(request)) = receive.recv().await else {
        panic!("Expected the frontend to receive a preparation request");
    };

    preparation.complete("wrong-token", true);
    assert!(!pending.is_finished());

    preparation.complete(&request, false);
    assert!(!pending.await.unwrap());
    assert!(matches!(
        receive.recv().await,
        Some(ExitEvent::Cancelled { cancelled }) if cancelled == request
    ));
    assert!(!preparation.attempt().prepare(SHORT_TIMEOUT).await);

    preparation.unsubscribe("wrong-subscription");
    assert!(!preparation.attempt().prepare(SHORT_TIMEOUT).await);

    preparation.unsubscribe(&subscription);
    assert!(preparation.attempt().prepare(SHORT_TIMEOUT).await);
}

#[tokio::test]
async fn accepted_native_exit_leaves_the_frontend_frozen() {
    let preparation = Arc::new(ExitPreparation::default());
    let (send, mut receive) = tokio::sync::mpsc::unbounded_channel();
    preparation.subscribe(move |event| send.send(event).is_ok());

    let exit = {
        let preparation = preparation.clone();
        tokio::spawn(async move {
            let attempt = preparation.attempt();
            assert!(attempt.prepare(ACK_TIMEOUT).await);
            attempt.commit();
        })
    };
    let Some(ExitEvent::Prepare(request)) = receive.recv().await else {
        panic!("Expected an exit preparation request");
    };
    preparation.complete(&request, true);

    exit.await.unwrap();
    assert!(receive.try_recv().is_err());
}
