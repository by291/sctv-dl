use std::io::ErrorKind;
use tauri::Runtime;
use tauri_plugin_store::Store;
use uuid::Uuid;

use crate::error::{AppError, Result};

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
