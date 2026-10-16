use std::{
    collections::{HashMap, VecDeque},
    future::Future,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::error::{AppError, ErrorCode, Result};

const EARLY_CANCELLATION_TTL: Duration = Duration::from_secs(60);
const MAX_EARLY_CANCELLATIONS: usize = 1024;

#[derive(Default)]
struct Requests {
    active: HashMap<Uuid, CancellationToken>,
    early: VecDeque<(Uuid, Instant)>,
}

impl Requests {
    fn prune(&mut self) {
        self.early
            .retain(|(_, created)| created.elapsed() < EARLY_CANCELLATION_TTL);
    }
}

#[derive(Default)]
pub struct RequestRegistry {
    requests: Mutex<Requests>,
}

/// Owns the active registration until its future completes or is dropped.
pub struct RequestGuard {
    registry: Arc<RequestRegistry>,
    id: Uuid,
    cancellation: CancellationToken,
}

fn request_id(value: &str) -> Result<Uuid> {
    Uuid::parse_str(value)
        .ok()
        .filter(|id| id.get_version_num() == 4 && id.get_variant() == uuid::Variant::RFC4122)
        .ok_or_else(|| AppError::new(ErrorCode::InvalidInput, "请求标识无效"))
}

impl RequestRegistry {
    pub fn register(self: &Arc<Self>, value: &str) -> Result<RequestGuard> {
        let id = request_id(value)?;
        let mut requests = self.requests.lock().unwrap();
        requests.prune();

        if requests.active.contains_key(&id) {
            return Err(AppError::new(ErrorCode::InvalidInput, "请求标识已被使用"));
        }

        let cancellation = CancellationToken::new();
        if let Some(index) = requests
            .early
            .iter()
            .position(|(request, _)| *request == id)
        {
            requests.early.remove(index);
            cancellation.cancel();
        }

        requests.active.insert(id, cancellation.clone());
        Ok(RequestGuard {
            registry: self.clone(),
            id,
            cancellation,
        })
    }

    pub fn cancel(&self, value: &str) -> Result<()> {
        let id = request_id(value)?;
        let mut requests = self.requests.lock().unwrap();
        requests.prune();

        if let Some(cancellation) = requests.active.get(&id) {
            cancellation.cancel();
        } else {
            // Native commands may arrive out of order; retain only bounded, expiring cancellations.
            requests.early.retain(|(request, _)| *request != id);
            requests.early.push_back((id, Instant::now()));
            while requests.early.len() > MAX_EARLY_CANCELLATIONS {
                requests.early.pop_front();
            }
        }
        Ok(())
    }
}

impl RequestGuard {
    pub async fn run<T>(self, operation: impl Future<Output = Result<T>>) -> Result<T> {
        tokio::select! {
            biased;
            _ = self.cancellation.cancelled() => Err(AppError::new(ErrorCode::Cancelled, "请求已取消")),
            result = operation => result,
        }
    }
}

impl Drop for RequestGuard {
    fn drop(&mut self) {
        self.registry
            .requests
            .lock()
            .unwrap()
            .active
            .remove(&self.id);
    }
}
