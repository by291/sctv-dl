use std::{
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::sync::oneshot;
use uuid::Uuid;

type Listener = Arc<dyn Fn(String) -> bool + Send + Sync>;

#[derive(Default)]
pub struct ExitPreparation {
    listener: Mutex<Option<(String, Listener)>>,
    pending: Mutex<Option<(String, oneshot::Sender<bool>)>>,
}

impl ExitPreparation {
    pub fn subscribe(&self, listener: impl Fn(String) -> bool + Send + Sync + 'static) -> String {
        let id = Uuid::new_v4().to_string();
        *self.listener.lock().unwrap() = Some((id.clone(), Arc::new(listener)));
        id
    }

    pub fn unsubscribe(&self, id: &str) {
        let mut listener = self.listener.lock().unwrap();
        if listener.as_ref().is_some_and(|(current, _)| current == id) {
            listener.take();
        }
    }

    pub fn complete(&self, id: &str, saved: bool) {
        let mut pending = self.pending.lock().unwrap();
        if pending.as_ref().is_some_and(|(current, _)| current == id)
            && let Some((_, send)) = pending.take()
        {
            let _ = send.send(saved);
        }
    }

    pub async fn prepare(&self, timeout: Duration) -> bool {
        let listener = self
            .listener
            .lock()
            .unwrap()
            .as_ref()
            .map(|(_, listener)| listener.clone());
        let Some(listener) = listener else {
            // No mounted frontend means no edits can be queued there.
            return true;
        };
        let id = Uuid::new_v4().to_string();
        let (send, receive) = oneshot::channel();
        *self.pending.lock().unwrap() = Some((id.clone(), send));
        let saved = listener(id.clone())
            && tokio::time::timeout(timeout, receive)
                .await
                .ok()
                .and_then(|result| result.ok())
                .unwrap_or(false);
        let mut pending = self.pending.lock().unwrap();
        if pending.as_ref().is_some_and(|(current, _)| current == &id) {
            pending.take();
        }
        saved
    }
}
