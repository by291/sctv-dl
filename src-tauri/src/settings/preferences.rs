use std::collections::HashSet;

use serde_json::Value;

use super::store::SettingsStore;
use crate::error::{AppError, ErrorCode, Result};

const PREFERENCES: &str = "preferences";
const MAX_WRITE_BYTES: usize = 16 * 1024;

#[derive(serde::Serialize)]
pub struct Preferences {
    quality: String,
    theme: String,
    favourites: Vec<String>,
}

impl Preferences {
    fn normalize(raw_preferences: &Value) -> Self {
        let quality = allowed_choice(&raw_preferences["quality"], "standard", &["smooth"]);
        let theme = allowed_choice(&raw_preferences["theme"], "system", &["light", "dark"]);
        let favourites = normalize_favourites(&raw_preferences["favourites"]);

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

pub(super) fn load_preferences(store: Option<&SettingsStore>) -> SettingsSnapshot {
    let raw_preferences = store
        .and_then(|store| store.get(PREFERENCES))
        .unwrap_or(&Value::Null);

    SettingsSnapshot {
        value: Preferences::normalize(raw_preferences),
        persisted: store.is_some_and(SettingsStore::is_durable),
    }
}

pub(super) fn save_preferences(store: &mut SettingsStore, submitted: Value) -> Result<()> {
    // Bound the untrusted IPC payload before normalization can discard unknown keys.
    let size = serde_json::to_vec(&submitted).map(|bytes| bytes.len());
    let is_valid_size = size.is_ok_and(|length| length <= MAX_WRITE_BYTES);
    if !submitted.is_object() || !is_valid_size {
        return Err(AppError::new(ErrorCode::InvalidInput, "设置数据无效或过大"));
    }

    let normalized = Preferences::normalize(&submitted);
    let preferences = serde_json::to_value(normalized)
        .map_err(|error| AppError::with_source(ErrorCode::InvalidInput, "设置数据无效", error))?;

    store.save_value(PREFERENCES, preferences, "无法保存设置，请检查应用数据目录")
}

fn allowed_choice<'a>(raw: &'a Value, default: &'static str, alternatives: &[&str]) -> &'a str {
    match raw.as_str() {
        Some(choice) if alternatives.contains(&choice) => choice,
        _ => default,
    }
}

fn normalize_favourites(raw: &Value) -> Vec<String> {
    let Some(values) = raw.as_array() else {
        return Vec::new();
    };

    // Match the shared schema's stable order and preserve the original string IDs.
    let mut seen = HashSet::new();
    let mut favourites = Vec::new();
    for value in values {
        let Some(id) = value.as_str() else {
            continue;
        };

        let is_string_id = !id.is_empty() && id.bytes().all(|byte| byte.is_ascii_digit());
        if is_string_id && seen.insert(id) {
            favourites.push(id.to_owned());
        }
    }

    favourites
}
