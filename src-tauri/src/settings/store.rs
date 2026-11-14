use std::{
    fs::{self, File},
    io::{self, ErrorKind},
    path::{Path, PathBuf},
};

use serde_json::{Map, Value};
use uuid::Uuid;

use crate::{
    error::{AppError, ErrorCode, Result},
    storage::{replacement_committed, write_json_atomic},
};

const INSTALLATION_ID: &str = "installationId";
const SAVE_IDENTITY_ERROR: &str = "无法保存桌面设备标识，请检查应用数据目录";

pub(super) struct SettingsStore {
    path: PathBuf,
    values: Map<String, Value>,
    is_durable: bool,
}

impl SettingsStore {
    pub(super) fn open(path: &Path) -> Result<(Self, String)> {
        let values = read_values(path).map_err(|error| {
            AppError::with_source(
                ErrorCode::Storage,
                "无法读取桌面应用数据，请检查应用数据目录",
                error,
            )
        })?;
        let mut store = Self {
            path: path.to_owned(),
            values,
            is_durable: true,
        };

        let identity = store.ensure_installation_id()?;

        Ok((store, identity))
    }

    pub(super) fn get(&self, key: &str) -> Option<&Value> {
        self.values.get(key)
    }

    pub(super) fn is_durable(&self) -> bool {
        self.is_durable
    }

    pub(super) fn save_value(
        &mut self,
        key: &str,
        value: Value,
        failure_message: &'static str,
    ) -> Result<()> {
        // Preserve private and unknown legacy keys in every replacement.
        let mut next = self.values.clone();
        next.insert(key.to_owned(), value);

        let result = write_json_atomic(&self.path, &next);
        let was_replaced = result.is_ok() || result.as_ref().is_err_and(replacement_committed);
        if was_replaced {
            // A sync failure after replacement still makes the new document authoritative.
            self.values = next;
            self.is_durable = result.is_ok();
        }

        result.map_err(|error| AppError::with_source(ErrorCode::Storage, failure_message, error))
    }

    fn ensure_installation_id(&mut self) -> Result<String> {
        let stored = self.get(INSTALLATION_ID).and_then(Value::as_str);
        if let Some(stored) = stored
            && let Ok(identity) = Uuid::parse_str(stored)
            && identity.get_version_num() == 4
            && identity.get_variant() == uuid::Variant::RFC4122
        {
            return Ok(identity.to_string());
        }

        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent).map_err(|error| {
                AppError::with_source(ErrorCode::Storage, SAVE_IDENTITY_ERROR, error)
            })?;
        }

        let identity = Uuid::new_v4().to_string();
        self.save_value(
            INSTALLATION_ID,
            Value::String(identity.clone()),
            SAVE_IDENTITY_ERROR,
        )?;

        Ok(identity)
    }
}

fn read_values(path: &Path) -> io::Result<Map<String, Value>> {
    let file = match File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == ErrorKind::NotFound => return Ok(Map::new()),
        Err(error) => return Err(error),
    };

    serde_json::from_reader(std::io::BufReader::new(file)).map_err(io::Error::other)
}
