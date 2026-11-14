use std::{
    sync::{Arc, Mutex},
    time::Duration,
};

use serde::Serialize;
use tokio::sync::oneshot;
use uuid::Uuid;

/// The event keeps preparation IDs as strings and adds a matching cancellation message.
#[derive(Serialize)]
#[serde(untagged)]
pub enum ExitEvent {
    Prepare(String),
    Cancelled { cancelled: String },
}

type Listener = Arc<dyn Fn(ExitEvent) -> bool + Send + Sync>;

#[derive(Default)]
pub struct ExitPreparation {
    listener: Mutex<Option<(String, Listener)>>,
    pending: Mutex<Option<(String, oneshot::Sender<bool>)>>,
}

/// Owns a frontend edit freeze until the native decision is committed or abandoned.
pub struct FrontendExitAttempt<'a> {
    owner: &'a ExitPreparation,
    id: String,
    listener: Option<Listener>,
    committed: bool,
}

impl ExitPreparation {
    /// Replaces the listener for the mounted frontend and returns its subscription ID.
    pub fn subscribe(
        &self,
        listener: impl Fn(ExitEvent) -> bool + Send + Sync + 'static,
    ) -> String {
        let id = Uuid::new_v4().to_string();
        *self.listener.lock().unwrap() = Some((id.clone(), Arc::new(listener)));

        id
    }

    /// Removes the subscription only if it still belongs to the caller.
    pub fn unsubscribe(&self, id: &str) {
        let mut listener = self.listener.lock().unwrap();
        if listener.as_ref().is_some_and(|(current, _)| current == id) {
            listener.take();
        }
    }

    /// Accepts the persistence result for the matching in-flight request.
    pub fn complete(&self, id: &str, saved: bool) {
        if let Some(send) = self.take_pending(id) {
            let _ = send.send(saved);
        }
    }

    /// Captures the current listener so cancellation reaches the same frontend.
    pub fn attempt(&self) -> FrontendExitAttempt<'_> {
        let listener = self
            .listener
            .lock()
            .unwrap()
            .as_ref()
            .map(|(_, listener)| listener.clone());

        FrontendExitAttempt {
            owner: self,
            id: Uuid::new_v4().to_string(),
            listener,
            committed: false,
        }
    }

    fn take_pending(&self, id: &str) -> Option<oneshot::Sender<bool>> {
        let mut pending = self.pending.lock().unwrap();
        if pending.as_ref().is_some_and(|(current, _)| current == id) {
            return pending.take().map(|(_, send)| send);
        }

        None
    }
}

impl FrontendExitAttempt<'_> {
    /// Freezes frontend edits and waits for the resulting persistence acknowledgement.
    pub async fn prepare(&self, timeout: Duration) -> bool {
        let Some(listener) = &self.listener else {
            // No mounted frontend means no edits can be queued there.
            return true;
        };

        let (send, receive) = oneshot::channel();
        *self.owner.pending.lock().unwrap() = Some((self.id.clone(), send));

        let delivered = listener(ExitEvent::Prepare(self.id.clone()));
        let saved =
            delivered && matches!(tokio::time::timeout(timeout, receive).await, Ok(Ok(true)));

        // Expire this acknowledgement without removing a different attempt.
        self.owner.take_pending(&self.id);

        saved
    }

    /// Keeps the frontend frozen while the native application exits.
    pub fn commit(mut self) {
        self.committed = true;
    }
}

impl Drop for FrontendExitAttempt<'_> {
    fn drop(&mut self) {
        self.owner.take_pending(&self.id);

        if !self.committed
            && let Some(listener) = &self.listener
        {
            listener(ExitEvent::Cancelled {
                cancelled: self.id.clone(),
            });
        }
    }
}
