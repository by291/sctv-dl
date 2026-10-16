use std::{
    io::ErrorKind,
    path::{Path, PathBuf},
    sync::Arc,
};
use tauri::{AppHandle, Runtime};
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_store::Store;
use uuid::Uuid;

use crate::error::{AppError, Result};

pub struct DesktopSettings<R: Runtime> {
    pub store: Result<Arc<Store<R>>>,
    selection: tokio::sync::Mutex<()>,
    pub writes: Arc<std::sync::Mutex<()>>,
}
impl<R: Runtime> DesktopSettings<R> {
    pub fn new(store: Result<Arc<Store<R>>>) -> Self {
        Self {
            store,
            selection: tokio::sync::Mutex::new(()),
            writes: Arc::default(),
        }
    }

    pub async fn choose(
        &self,
        app: &AppHandle<R>,
        only_if_missing: bool,
    ) -> Result<Option<PathBuf>> {
        let _selection = self.selection.lock().await;
        let store = self.store.as_ref().map_err(Clone::clone)?;
        if only_if_missing && let Some(path) = download_directory(store)? {
            return Ok(Some(path));
        }
        let (sender, receiver) = tokio::sync::oneshot::channel();
        app.dialog()
            .file()
            .set_title("选择视频下载文件夹")
            .pick_folder(move |path| {
                let _ = sender.send(path);
            });
        let path = receiver
            .await
            .map_err(|_| AppError::new("storage", "无法打开文件夹选择器"))?;
        let Some(path) = path else {
            return Ok(None);
        };
        let path = path
            .into_path()
            .map_err(|_| AppError::new("storage", "请选择本机文件夹"))?;
        let _write = self.writes.lock().unwrap();
        save_download_directory(store, &path)?;
        download_directory(store)
    }
}

pub fn download_directory<R: Runtime>(store: &Store<R>) -> Result<Option<PathBuf>> {
    let Some(value) = store.get("downloadDirectory") else {
        return Ok(None);
    };
    let path = value
        .as_str()
        .filter(|path| !path.is_empty())
        .ok_or_else(|| AppError::new("storage", "保存的下载目录无效，请重新选择"))?;
    let path = Path::new(path)
        .canonicalize()
        .map_err(|_| AppError::new("storage", "下载目录已不可用，请在设置中重新选择"))?;
    if !path.is_dir() {
        return Err(AppError::new("storage", "下载位置不是文件夹，请重新选择"));
    }
    Ok(Some(path))
}

pub fn save_download_directory<R: Runtime>(store: &Store<R>, path: &Path) -> Result<()> {
    let path = path
        .canonicalize()
        .map_err(|_| AppError::new("storage", "下载目录已不可用，请重新选择"))?;
    let text = path
        .to_str()
        .ok_or_else(|| AppError::new("storage", "无法保存此目录路径，请选择其他文件夹"))?;
    // Validate write access without acquiring the manager's long-lived directory lock.
    tempfile::Builder::new()
        .prefix(".sctv-dl-directory-check-")
        .tempfile_in(&path)
        .and_then(|file| file.close())
        .map_err(|_| AppError::new("storage", "下载目录无法写入，请选择其他文件夹"))?;
    let previous = store.get("downloadDirectory");
    store.set("downloadDirectory", serde_json::json!(text));
    if store.save().is_err() {
        if let Some(previous) = previous {
            store.set("downloadDirectory", previous);
        } else {
            store.delete("downloadDirectory");
        }
        store.close_resource();
        return Err(AppError::new(
            "storage",
            "无法保存下载目录，请检查应用数据目录",
        ));
    }
    Ok(())
}

pub fn installation_id<R: Runtime>(store: &Store<R>) -> Result<String> {
    let result = read_installation_id(store);
    if result.is_err() {
        // The plugin also saves registered stores on exit, even with auto-save disabled.
        store.close_resource();
    }
    result
}

fn read_installation_id<R: Runtime>(store: &Store<R>) -> Result<String> {
    // Store construction ignores load errors; do not silently rotate an unreadable identity.
    match store.reload() {
        Ok(()) => {}
        Err(tauri_plugin_store::Error::Io(error)) if error.kind() == ErrorKind::NotFound => {}
        Err(_) => {
            return Err(AppError::new(
                "storage",
                "无法读取桌面应用数据，请检查应用数据目录",
            ));
        }
    }
    let stored = store
        .get("installationId")
        .and_then(|value| value.as_str().and_then(|id| Uuid::parse_str(id).ok()));
    let id = stored
        .filter(|id| id.get_version_num() == 4 && id.get_variant() == uuid::Variant::RFC4122)
        .unwrap_or_else(Uuid::new_v4)
        .to_string();
    store.set("installationId", serde_json::json!(id));
    store
        .save()
        .map_err(|_| AppError::new("storage", "无法保存桌面设备标识，请检查应用数据目录"))?;
    Ok(id)
}

#[derive(serde::Serialize)]
pub struct Preferences {
    quality: String,
    theme: String,
    favourites: Vec<String>,
}

impl Preferences {
    fn normalize(value: &serde_json::Value) -> Self {
        let quality = value["quality"]
            .as_str()
            .filter(|value| ["standard", "smooth"].contains(value))
            .unwrap_or("standard");
        let theme = value["theme"]
            .as_str()
            .filter(|value| ["system", "light", "dark"].contains(value))
            .unwrap_or("system");
        let mut favourites = Vec::new();
        if let Some(values) = value["favourites"].as_array() {
            for value in values {
                if let Some(id) = value
                    .as_str()
                    .filter(|id| !id.is_empty() && id.bytes().all(|byte| byte.is_ascii_digit()))
                    && !favourites.iter().any(|previous| previous == id)
                {
                    favourites.push(id.to_owned());
                }
            }
        }
        Self {
            quality: quality.into(),
            theme: theme.into(),
            favourites,
        }
    }
}

#[derive(serde::Serialize)]
pub struct SettingsSnapshot {
    value: Preferences,
    persisted: bool,
}

pub fn load_preferences<R: Runtime>(store: Result<&Store<R>>) -> SettingsSnapshot {
    let persisted = store.is_ok();
    let value = store
        .ok()
        .and_then(|store| store.get("preferences"))
        .unwrap_or_default();
    SettingsSnapshot {
        value: Preferences::normalize(&value),
        persisted,
    }
}

pub fn save_preferences<R: Runtime>(store: &Store<R>, value: serde_json::Value) -> Result<()> {
    if !value.is_object()
        || serde_json::to_vec(&value).map_or(true, |bytes| bytes.len() > 16 * 1024)
    {
        return Err(AppError::new("invalid-input", "设置数据无效或过大"));
    }
    let value = serde_json::to_value(Preferences::normalize(&value))
        .map_err(|_| AppError::new("invalid-input", "设置数据无效"))?;
    let previous = store.get("preferences");
    store.set("preferences", value);
    if store.save().is_err() {
        if let Some(previous) = previous {
            store.set("preferences", previous);
        } else {
            store.delete("preferences");
        }
        store.close_resource();
        return Err(AppError::new("storage", "无法保存设置，请检查应用数据目录"));
    }
    Ok(())
}
