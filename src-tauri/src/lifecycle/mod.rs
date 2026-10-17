#[cfg(target_os = "macos")]
pub mod macos;
mod preparation;
mod shell;

pub use preparation::ExitPreparation;
pub use shell::{install_menu, request_exit};

use std::{
    future::Future,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};
use tokio::sync::{OwnedRwLockReadGuard, RwLock};

use crate::{
    downloads::DownloadManager,
    error::{AppError, ErrorCode, Result},
};

#[derive(Default)]
pub struct ExitController {
    operations: Arc<RwLock<()>>,
    closing: AtomicBool,
    committed: AtomicBool,
    frozen: AtomicBool,
}

/// Keeps an admitted operation visible to exit until its owner finishes.
/// Blocking workers must retain this guard if their awaiting future is dropped.
pub struct OperationGuard {
    _admission: OwnedRwLockReadGuard<()>,
}

impl ExitController {
    /// Admits new work only while the application is open.
    pub async fn enter(&self) -> Result<OperationGuard> {
        if self.closing.load(Ordering::SeqCst) {
            return Err(closing());
        }
        let guard = self.operations.clone().read_owned().await;
        if self.closing.load(Ordering::SeqCst) {
            return Err(closing());
        }
        Ok(OperationGuard { _admission: guard })
    }

    /// Allows queued preference saves during frontend exit preparation.
    pub async fn enter_save(&self) -> Result<OperationGuard> {
        if self.frozen.load(Ordering::SeqCst) || self.committed() {
            return Err(closing());
        }
        let guard = self.operations.clone().read_owned().await;
        if self.frozen.load(Ordering::SeqCst) || self.committed() {
            return Err(closing());
        }
        Ok(OperationGuard { _admission: guard })
    }

    pub fn begin(self: &Arc<Self>) -> Option<ExitRequest> {
        self.closing
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .ok()?;
        Some(ExitRequest {
            controller: self.clone(),
        })
    }

    pub fn committed(&self) -> bool {
        self.committed.load(Ordering::SeqCst)
    }
}

fn closing() -> AppError {
    AppError::new(ErrorCode::Cancelled, "应用正在退出")
}

/// Owns one exit attempt. Dropping an uncommitted attempt reopens admission.
pub struct ExitRequest {
    controller: Arc<ExitController>,
}

impl ExitRequest {
    pub async fn complete<F, Fut>(self, downloads: &DownloadManager, confirm: F) -> bool
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = bool>,
    {
        self.complete_prepared(downloads, async { true }, |_| confirm())
            .await
    }

    /// Drains frontend saves, freezes admission, and waits for existing work.
    /// A successful return follows durable download checkpoints and awaited cleanup.
    /// Rejecting confirmation restores admission when this attempt is dropped.
    pub async fn complete_prepared<P, F, Fut>(
        self,
        downloads: &DownloadManager,
        prepare: P,
        confirm: F,
    ) -> bool
    where
        P: Future<Output = bool>,
        F: FnOnce(bool) -> Fut,
        Fut: Future<Output = bool>,
    {
        self.complete_with_recovery(downloads, prepare, confirm, |_| async { false })
            .await
    }

    /// Failed checkpoints need a separate decision after writers have settled.
    pub async fn complete_with_recovery<P, F, Fut, G, Force>(
        self,
        downloads: &DownloadManager,
        prepare: P,
        confirm: F,
        force: G,
    ) -> bool
    where
        P: Future<Output = bool>,
        F: FnOnce(bool) -> Fut,
        Fut: Future<Output = bool>,
        G: FnOnce(AppError) -> Force,
        Force: Future<Output = bool>,
    {
        // Drain frontend save queues before refusing new preference writes.
        let saved = prepare.await;
        self.controller.frozen.store(true, Ordering::SeqCst);
        // Existing picker/prepare/save work must settle before the final task snapshot.
        let _operations = self.controller.operations.clone().write_owned().await;
        if (!saved || downloads.has_active()) && !confirm(saved).await {
            return false;
        }
        let _admission = DownloadAdmission(downloads);
        if let Err(error) = downloads.prepare_shutdown().await
            && !force(error.reported("prepare downloads for exit")).await
        {
            return false;
        }
        downloads.shutdown().await;
        self.controller.committed.store(true, Ordering::SeqCst);
        true
    }
}

/// Also reopens admission when an exit future is cancelled during checkpointing.
struct DownloadAdmission<'a>(&'a DownloadManager);

impl Drop for DownloadAdmission<'_> {
    fn drop(&mut self) {
        self.0.reopen_admission();
    }
}

impl Drop for ExitRequest {
    fn drop(&mut self) {
        if !self.controller.committed() {
            self.controller.frozen.store(false, Ordering::SeqCst);
            self.controller.closing.store(false, Ordering::SeqCst);
        }
    }
}
