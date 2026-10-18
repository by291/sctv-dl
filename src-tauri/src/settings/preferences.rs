use tauri::Runtime;
use tauri_plugin_store::Store;

use crate::error::{AppError, ErrorCode, Result};

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
    pub(super) value: Preferences,
    pub(super) persisted: bool,
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
        return Err(AppError::new(ErrorCode::InvalidInput, "设置数据无效或过大"));
    }

    let value = serde_json::to_value(Preferences::normalize(&value))
        .map_err(|error| AppError::with_source(ErrorCode::InvalidInput, "设置数据无效", error))?;

    super::store::save_value(
        store,
        "preferences",
        value,
        "无法保存设置，请检查应用数据目录",
    )
}
