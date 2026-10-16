mod directory;
mod preferences;
mod store;

pub use directory::{download_directory, save_download_directory};
pub use preferences::{Preferences, SettingsSnapshot, load_preferences, save_preferences};
pub use store::installation_id;

use std::{path::PathBuf, sync::Arc};

use tauri::{AppHandle, Runtime};
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_store::Store;

use crate::{
    error::{AppError, ErrorCode, Result},
    lifecycle::OperationGuard,
};

/// Owns the shared Store and serializes complete preference/directory transactions.
pub struct DesktopSettings<R: Runtime> {
    store: Result<Arc<Store<R>>>,
    selection: Arc<tokio::sync::Mutex<()>>,
    writes: Arc<std::sync::Mutex<()>>,
}

impl<R: Runtime> DesktopSettings<R> {
    pub fn new(store: Result<Arc<Store<R>>>) -> Self {
        Self {
            store,
            selection: Arc::default(),
            writes: Arc::default(),
        }
    }

    pub async fn load(&self) -> SettingsSnapshot {
        self.blocking((), "load preferences", "读取设置异常终止", |store| {
            Ok(load_preferences(store))
        })
        .await
        .unwrap_or_else(|error| load_preferences::<R>(Err(error)))
    }

    /// Completes persistence before releasing admission, even if the caller disappears.
    pub async fn save(&self, value: serde_json::Value, operation: OperationGuard) -> Result<()> {
        self.blocking(
            operation,
            "save preferences",
            "保存设置异常终止",
            move |store| save_preferences(store?, value),
        )
        .await
    }

    pub async fn directory(&self) -> Result<Option<PathBuf>> {
        self.blocking(
            (),
            "read download directory",
            "读取下载目录异常终止",
            |store| download_directory(store?),
        )
        .await
    }

    pub async fn choose_download_directory(
        &self,
        app: &AppHandle<R>,
        operation: Arc<OperationGuard>,
    ) -> Result<Option<PathBuf>> {
        self.select_directory(app, false, operation).await
    }

    pub async fn ensure_download_directory(
        &self,
        app: &AppHandle<R>,
        operation: Arc<OperationGuard>,
    ) -> Result<Option<PathBuf>> {
        self.select_directory(app, true, operation).await
    }

    async fn select_directory(
        &self,
        app: &AppHandle<R>,
        only_if_missing: bool,
        operation: Arc<OperationGuard>,
    ) -> Result<Option<PathBuf>> {
        let selection = self.selection.clone().lock_owned().await;
        if only_if_missing {
            let saved = self
                .blocking(
                    operation.clone(),
                    "read download directory",
                    "读取下载目录异常终止",
                    |store| download_directory(store?),
                )
                .await?;
            if saved.is_some() {
                return Ok(saved);
            }
        }

        let Some(path) = pick_directory(app).await? else {
            return Ok(None);
        };

        self.persist_directory(path, operation, selection).await
    }

    async fn persist_directory(
        &self,
        path: PathBuf,
        operation: Arc<OperationGuard>,
        selection: tokio::sync::OwnedMutexGuard<()>,
    ) -> Result<Option<PathBuf>> {
        // The worker retains both exit admission and picker serialization until
        // persistence settles; dropping its awaiting command cannot release either.
        self.blocking(
            (operation, selection),
            "save download directory",
            "保存下载目录异常终止",
            move |store| {
                let store = store?;
                save_download_directory(store, &path)?;
                download_directory(store)
            },
        )
        .await
    }

    async fn blocking<T, G>(
        &self,
        guard: G,
        operation: &'static str,
        failure_message: &'static str,
        action: impl FnOnce(Result<&Store<R>>) -> Result<T> + Send + 'static,
    ) -> Result<T>
    where
        T: Send + 'static,
        G: Send + 'static,
    {
        let store = self.store.clone();
        let writes = self.writes.clone();

        tokio::task::spawn_blocking(move || {
            let _operation = guard;
            let _write = writes.lock().unwrap();
            let store = store
                .as_ref()
                .map(|store| store.as_ref())
                .map_err(|error| error.clone().reported(operation));
            action(store).map_err(|error| error.reported(operation))
        })
        .await
        .map_err(|error| {
            AppError::with_source(ErrorCode::Storage, failure_message, error).reported(operation)
        })?
    }
}

async fn pick_directory<R: Runtime>(app: &AppHandle<R>) -> Result<Option<PathBuf>> {
    let (sender, receiver) = tokio::sync::oneshot::channel();
    app.dialog()
        .file()
        .set_title("选择视频下载文件夹")
        .pick_folder(move |path| {
            let _ = sender.send(path);
        });

    receiver
        .await
        .map_err(|error| {
            AppError::with_source(ErrorCode::Storage, "无法打开文件夹选择器", error)
                .reported("choose download directory")
        })?
        .map(|path| {
            path.into_path().map_err(|error| {
                AppError::with_source(ErrorCode::Storage, "请选择本机文件夹", error)
                    .reported("choose download directory")
            })
        })
        .transpose()
}

#[cfg(test)]
mod tests;
