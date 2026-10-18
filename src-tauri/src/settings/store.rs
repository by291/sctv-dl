use std::io::ErrorKind;

use tauri::Runtime;
use tauri_plugin_store::Store;
use uuid::Uuid;

use crate::error::{AppError, ErrorCode, Result};

pub(super) fn save_value<R: Runtime>(
    store: &Store<R>,
    key: &'static str,
    value: serde_json::Value,
    failure_message: &'static str,
) -> Result<()> {
    let previous = store.get(key);
    store.set(key, value);

    if let Err(error) = store.save() {
        if let Some(previous) = previous {
            store.set(key, previous);
        } else {
            store.delete(key);
        }

        // The plugin saves registered stores on exit even with auto-save disabled.
        // Unregister failed writes so that shutdown cannot overwrite a damaged file.
        store.close_resource();
        return Err(AppError::with_source(
            ErrorCode::Storage,
            failure_message,
            error,
        ));
    }

    Ok(())
}

/// Loads one persisted identity before any metadata command can access the service.
pub fn installation_id<R: Runtime>(store: &Store<R>) -> Result<String> {
    let result = read_installation_id(store);
    if result.is_err() {
        store.close_resource();
    }

    result.map_err(|error| error.reported("load installation identity"))
}

fn read_installation_id<R: Runtime>(store: &Store<R>) -> Result<String> {
    // Store construction ignores load errors; never rotate an unreadable identity.
    match store.reload() {
        Ok(()) => {}
        Err(tauri_plugin_store::Error::Io(error)) if error.kind() == ErrorKind::NotFound => {}
        Err(error) => {
            return Err(AppError::with_source(
                ErrorCode::Storage,
                "无法读取桌面应用数据，请检查应用数据目录",
                error,
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
    store.save().map_err(|error| {
        AppError::with_source(
            ErrorCode::Storage,
            "无法保存桌面设备标识，请检查应用数据目录",
            error,
        )
    })?;

    Ok(id)
}
