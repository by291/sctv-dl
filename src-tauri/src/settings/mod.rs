mod directory;
mod preferences;
mod store;

pub use preferences::{Preferences, SettingsSnapshot};

use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

use serde_json::Value;
use tauri::{AppHandle, Runtime};
use tauri_plugin_dialog::DialogExt;

use crate::{
    error::{AppError, ErrorCode, Result},
    lifecycle::OperationGuard,
};

use self::{
    directory::{download_directory, save_download_directory},
    preferences::{load_preferences, save_preferences},
    store::SettingsStore,
};

const READ_PREFERENCES: StoreOperation = StoreOperation {
    description: "load preferences",
    worker_failure: "读取设置异常终止",
};
const WRITE_PREFERENCES: StoreOperation = StoreOperation {
    description: "save preferences",
    worker_failure: "保存设置异常终止",
};
const READ_DIRECTORY: StoreOperation = StoreOperation {
    description: "read download directory",
    worker_failure: "读取下载目录异常终止",
};
const WRITE_DIRECTORY: StoreOperation = StoreOperation {
    description: "save download directory",
    worker_failure: "保存下载目录异常终止",
};

#[derive(Clone, Copy)]
struct StoreOperation {
    description: &'static str,
    worker_failure: &'static str,
}

enum DirectorySelection {
    AlwaysPrompt,
    PreferSaved,
}

/// Owns the desktop settings document and serializes full read/write transactions.
pub struct DesktopSettings {
    store: Arc<Mutex<Result<SettingsStore>>>,
    selection: Arc<tokio::sync::Mutex<()>>,
}

impl DesktopSettings {
    /// Opens the existing settings document and ensures one persisted installation identity.
    pub fn open(path: &Path) -> Result<(Self, String)> {
        let (store, identity) = SettingsStore::open(path)
            .map_err(|error| error.reported("open desktop data and load installation identity"))?;

        Ok((Self::new(Ok(store)), identity))
    }

    /// Serves defaults without allowing writes when the saved document cannot be opened.
    pub fn unavailable(error: AppError) -> Self {
        Self::new(Err(error))
    }

    fn new(store: Result<SettingsStore>) -> Self {
        Self {
            store: Arc::new(Mutex::new(store)),
            selection: Arc::default(),
        }
    }

    /// Loads public preferences or returns flagged defaults when storage is unavailable.
    pub async fn load(&self) -> SettingsSnapshot {
        self.blocking((), READ_PREFERENCES, |store| {
            Ok(load_preferences(store.ok().map(|store| &*store)))
        })
        .await
        .unwrap_or_else(|_| load_preferences(None))
    }

    /// Completes persistence before releasing admission, even if the caller disappears.
    pub async fn save(&self, value: Value, operation: OperationGuard) -> Result<()> {
        self.blocking(operation, WRITE_PREFERENCES, move |store| {
            save_preferences(store?, value)
        })
        .await
    }

    /// Returns the validated saved directory, if the user has picked one.
    pub async fn directory(&self) -> Result<Option<PathBuf>> {
        self.read_directory(()).await
    }

    /// Lets the user replace the active download directory.
    pub async fn choose_download_directory<R: Runtime>(
        &self,
        app: &AppHandle<R>,
        operation: Arc<OperationGuard>,
    ) -> Result<Option<PathBuf>> {
        self.select_directory(app, DirectorySelection::AlwaysPrompt, operation)
            .await
    }

    /// Reuses the saved directory or prompts for one when none has been chosen.
    pub async fn ensure_download_directory<R: Runtime>(
        &self,
        app: &AppHandle<R>,
        operation: Arc<OperationGuard>,
    ) -> Result<Option<PathBuf>> {
        self.select_directory(app, DirectorySelection::PreferSaved, operation)
            .await
    }

    async fn select_directory<R: Runtime>(
        &self,
        app: &AppHandle<R>,
        mode: DirectorySelection,
        operation: Arc<OperationGuard>,
    ) -> Result<Option<PathBuf>> {
        let selection = self.selection.clone().lock_owned().await;

        // Serialize the read and picker together so queued requests can reuse the choice.
        if matches!(mode, DirectorySelection::PreferSaved) {
            let saved = self.read_directory(operation.clone()).await?;
            if saved.is_some() {
                return Ok(saved);
            }
        }

        let Some(path) = pick_directory(app).await? else {
            return Ok(None);
        };

        self.persist_directory(path, operation, selection).await
    }

    async fn read_directory(&self, guard: impl Send + 'static) -> Result<Option<PathBuf>> {
        self.blocking(guard, READ_DIRECTORY, |store| download_directory(store?))
            .await
    }

    async fn persist_directory(
        &self,
        path: PathBuf,
        operation: Arc<OperationGuard>,
        selection: tokio::sync::OwnedMutexGuard<()>,
    ) -> Result<Option<PathBuf>> {
        // The worker retains both exit admission and picker serialization until
        // persistence settles; dropping its awaiting command cannot release either.
        self.blocking((operation, selection), WRITE_DIRECTORY, move |store| {
            let store = store?;
            save_download_directory(store, &path)?;

            download_directory(store)
        })
        .await
    }

    async fn blocking<T: Send + 'static>(
        &self,
        guard: impl Send + 'static,
        operation: StoreOperation,
        action: impl FnOnce(Result<&mut SettingsStore>) -> Result<T> + Send + 'static,
    ) -> Result<T> {
        let store = self.store.clone();
        let worker = tokio::task::spawn_blocking(move || {
            let _admission = guard;
            // Hold the document lock across the entire operation, including its disk commit.
            let mut locked_store = store.lock().unwrap();
            let document = locked_store
                .as_mut()
                .map_err(|error| error.clone().reported(operation.description));

            action(document).map_err(|error| error.reported(operation.description))
        });

        worker.await.map_err(|error| {
            AppError::with_source(ErrorCode::Storage, operation.worker_failure, error)
                .reported(operation.description)
        })?
    }
}

async fn pick_directory<R: Runtime>(app: &AppHandle<R>) -> Result<Option<PathBuf>> {
    let (sender, receiver) = tokio::sync::oneshot::channel();
    let picker = app.dialog().file().set_title("选择视频下载文件夹");
    picker.pick_folder(move |path| {
        let _ = sender.send(path);
    });

    let selected = receiver.await.map_err(|error| {
        AppError::with_source(ErrorCode::Storage, "无法打开文件夹选择器", error)
            .reported("choose download directory")
    })?;
    let Some(path) = selected else {
        return Ok(None);
    };

    let location = path.into_path().map_err(|error| {
        AppError::with_source(ErrorCode::Storage, "请选择本机文件夹", error)
            .reported("choose download directory")
    })?;

    Ok(Some(location))
}

#[cfg(test)]
mod tests;
