mod models;
pub use models::*;

use crate::{
    error::{AppError, ErrorCode, Result},
    lifecycle::OperationGuard,
    storage::{read_json, write_json_atomic},
};
use chrono::{SecondsFormat, Utc};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs::{File, OpenOptions},
    path::PathBuf,
    sync::{Arc, Mutex},
};
use uuid::Uuid;

const MAX_BYTES: usize = 20 * 1024 * 1024;
const WARNING: &str = "节目缓存无法保存到本地，当前数据仅在本次会话中保留";
#[derive(Clone, Deserialize, Serialize)]
struct Entry {
    file: String,
    bytes: usize,
    accessed: u64,
}
#[derive(Clone, Deserialize, Serialize)]
struct Manifest {
    version: u32,
    epoch: String,
    clock: u64,
    entries: BTreeMap<String, Entry>,
    browse: BTreeMap<String, BrowseState>,
}
impl Default for Manifest {
    fn default() -> Self {
        Self {
            version: 1,
            epoch: Uuid::new_v4().to_string(),
            clock: 0,
            entries: BTreeMap::new(),
            browse: BTreeMap::new(),
        }
    }
}
struct State {
    manifest: Manifest,
    memory: BTreeMap<String, Snapshot>,
    warning: Option<String>,
}
struct Owner {
    root: PathBuf,
    writable: bool,
    _lock: Option<File>,
    state: Mutex<State>,
}
/// All I/O and lock waits run in a blocking worker retaining its exit operation
/// guard. The owner serializes manifest changes through completion, including clear.
#[derive(Clone)]
pub struct ProgrammeCacheService(Arc<Owner>);
impl ProgrammeCacheService {
    pub async fn open(root: PathBuf) -> Self {
        match tokio::task::spawn_blocking(move || Self::open_blocking(root)).await {
            Ok(service) => service,
            Err(error) => {
                Self::unavailable(AppError::with_source(ErrorCode::Storage, WARNING, error))
            }
        }
    }
    pub fn unavailable(error: AppError) -> Self {
        Self(Arc::new(Owner {
            root: PathBuf::new(),
            writable: false,
            _lock: None,
            state: Mutex::new(State {
                manifest: Manifest::default(),
                memory: BTreeMap::new(),
                warning: Some(error.reported("open programme cache").message),
            }),
        }))
    }
    fn open_blocking(root: PathBuf) -> Self {
        let lock = (|| {
            std::fs::create_dir_all(&root)?;
            let file = OpenOptions::new()
                .read(true)
                .write(true)
                .create(true)
                .truncate(false)
                .open(root.join("cache.lock"))?;
            file.try_lock()?;
            Ok::<_, std::io::Error>(file)
        })();
        let writable = lock.is_ok();
        let mut warning = (!writable).then(|| WARNING.to_owned());
        let manifest = match read_json::<Manifest>(&root.join("manifest.json"), 1024 * 1024) {
            Ok(Some(value)) if valid_manifest(&value) => value,
            Ok(None) => Manifest::default(),
            _ => {
                warning = Some("节目缓存索引已损坏，已开始新的缓存代际".into());
                Manifest::default()
            }
        };
        if writable && let Err(error) = write_json_atomic(&root.join("manifest.json"), &manifest) {
            AppError::with_source(ErrorCode::Storage, WARNING, error)
                .reported("initialize programme cache");
            warning = Some(WARNING.into());
        }
        Self(Arc::new(Owner {
            root,
            writable,
            _lock: lock.ok(),
            state: Mutex::new(State {
                manifest,
                memory: BTreeMap::new(),
                warning,
            }),
        }))
    }
    async fn run<T: Send + 'static>(
        &self,
        operation: OperationGuard,
        action: impl FnOnce(&Owner, &mut State) -> Result<T> + Send + 'static,
    ) -> Result<T> {
        let owner = self.0.clone();
        tokio::task::spawn_blocking(move || {
            let _operation = operation;
            let mut state = owner.state.lock().unwrap();
            action(&owner, &mut state)
        })
        .await
        .map_err(|error| AppError::with_source(ErrorCode::Storage, WARNING, error))?
    }
    pub async fn read(&self, key: CacheKey, operation: OperationGuard) -> Result<CacheRead> {
        let name = key.name()?;
        self.run(operation, move |owner, state| {
            let snapshot = load(owner, state, &name);
            let memory_only = state.memory.contains_key(&name) || !owner.writable;
            if snapshot.is_some() {
                let mut next = state.manifest.clone();
                next.clock = next.clock.saturating_add(1);
                if let Some(entry) = next.entries.get_mut(&name) {
                    entry.accessed = next.clock;
                }
                if owner.writable && commit(owner, state, &next).is_ok() {
                    state.manifest = next;
                }
            }
            Ok(CacheRead {
                epoch: state.manifest.epoch.clone(),
                snapshot,
                persisted: !memory_only,
                warning: state.warning.clone(),
            })
        })
        .await
    }
    pub async fn write(
        &self,
        payload: CachePayload,
        expected_epoch: String,
        operation: OperationGuard,
    ) -> Result<CacheWriteResult> {
        payload.validate()?;
        let name = payload.key().name()?;
        self.run(operation, move |owner, state| {
            let previous = load(owner, state, &name);
            if expected_epoch != state.manifest.epoch {
                return Ok(CacheWriteResult {
                    epoch: state.manifest.epoch.clone(),
                    snapshot: previous,
                    accepted: false,
                    persisted: owner.writable,
                    warning: state.warning.clone(),
                });
            }
            let revision = previous
                .filter(|snapshot| snapshot.payload == payload)
                .map(|snapshot| snapshot.revision)
                .unwrap_or_else(|| Uuid::new_v4().to_string());
            let snapshot = Snapshot {
                payload,
                version: 1,
                revision,
                fetched_at: Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true),
            };
            let bytes = serde_json::to_vec(&snapshot)
                .map_err(|error| AppError::with_source(ErrorCode::Storage, WARNING, error))?
                .len();
            if bytes > MAX_BYTES {
                return Ok(CacheWriteResult {
                    epoch: state.manifest.epoch.clone(),
                    snapshot: Some(snapshot),
                    accepted: true,
                    persisted: false,
                    warning: Some("节目数据超过缓存容量，本次结果未保存".into()),
                });
            }
            let mut next = state.manifest.clone();
            next.clock = next.clock.saturating_add(1);
            let file = format!("{}.json", Uuid::new_v4());
            next.entries.insert(
                name.clone(),
                Entry {
                    file: file.clone(),
                    bytes,
                    accessed: next.clock,
                },
            );
            trim(&mut next);
            let persisted = owner.writable
                && std::fs::create_dir_all(owner.root.join(&next.epoch))
                    .and_then(|()| {
                        write_json_atomic(&owner.root.join(&next.epoch).join(&file), &snapshot)
                    })
                    .and_then(|()| write_json_atomic(&owner.root.join("manifest.json"), &next))
                    .map_err(|error| {
                        state.warning = Some(WARNING.into());
                        AppError::with_source(ErrorCode::Storage, WARNING, error)
                            .reported("write programme cache");
                    })
                    .is_ok();
            if persisted {
                cleanup_entries(owner, &state.manifest, &next);
                state.manifest = next;
                state.memory.remove(&name);
            } else {
                state.memory.insert(name.clone(), snapshot.clone());
                // A failed durable write does not replace its committed file.
                // The bounded in-memory index remains usable in this process.
                while state.memory.len() > 200
                    || state
                        .memory
                        .values()
                        .map(|value| {
                            serde_json::to_vec(value).map_or(MAX_BYTES, |bytes| bytes.len())
                        })
                        .sum::<usize>()
                        > MAX_BYTES
                {
                    let oldest = state.memory.keys().find(|key| *key != &name).cloned();
                    if let Some(key) = oldest {
                        state.memory.remove(&key);
                    } else {
                        break;
                    }
                }
                state.warning = Some(WARNING.into());
            }
            Ok(CacheWriteResult {
                epoch: state.manifest.epoch.clone(),
                snapshot: Some(snapshot),
                accepted: true,
                persisted,
                warning: state.warning.clone(),
            })
        })
        .await
    }
    pub async fn read_browse(
        &self,
        programme_id: String,
        operation: OperationGuard,
    ) -> Result<BrowseRead> {
        crate::programmes::validate_id(&programme_id)?;
        self.run(operation, move |owner, state| {
            Ok(BrowseRead {
                epoch: state.manifest.epoch.clone(),
                value: state.manifest.browse.get(&programme_id).cloned(),
                persisted: owner.writable && state.warning.is_none(),
                warning: state.warning.clone(),
            })
        })
        .await
    }
    pub async fn write_browse(
        &self,
        value: BrowseState,
        expected_epoch: String,
        operation: OperationGuard,
    ) -> Result<WriteResult> {
        value.validate()?;
        self.run(operation, move |owner, state| {
            if expected_epoch != state.manifest.epoch {
                return Ok(WriteResult {
                    accepted: false,
                    persisted: owner.writable,
                });
            }
            let mut next = state.manifest.clone();
            next.browse.insert(value.programme_id.clone(), value);
            while next.browse.len() > 100 {
                let oldest = next
                    .browse
                    .iter()
                    .min_by(|a, b| a.1.visited_at.cmp(&b.1.visited_at))
                    .map(|(key, _)| key.clone())
                    .unwrap();
                next.browse.remove(&oldest);
            }
            let persisted = owner.writable && commit(owner, state, &next).is_ok();
            state.manifest = next;
            Ok(WriteResult {
                accepted: true,
                persisted,
            })
        })
        .await
    }
    pub async fn clear(&self, operation: OperationGuard) -> Result<ClearResult> {
        self.run(operation, |owner, state| {
            let next = Manifest::default();
            if !owner.writable {
                return Err(AppError::new(
                    ErrorCode::Storage,
                    "无法清除本地节目缓存，请重试",
                ));
            }
            if let Err(error) = write_json_atomic(&owner.root.join("manifest.json"), &next) {
                // Atomic replacement may have completed before directory sync failed.
                // Reconcile the durable fence, never revive an earlier generation.
                if let Ok(Some(actual)) =
                    read_json::<Manifest>(&owner.root.join("manifest.json"), 1024 * 1024)
                    && valid_manifest(&actual)
                {
                    state.manifest = actual;
                    state.memory.clear();
                }
                return Err(AppError::with_source(
                    ErrorCode::Storage,
                    "缓存清除未完成，请重试",
                    error,
                ));
            }
            state.manifest = next;
            state.memory.clear();
            state.warning = None;
            for entry in std::fs::read_dir(&owner.root).map_err(storage_error)? {
                let entry = entry.map_err(storage_error)?;
                let name = entry.file_name().to_string_lossy().into_owned();
                if name != state.manifest.epoch
                    && Uuid::parse_str(&name).is_ok()
                    && entry.file_type().map_err(storage_error)?.is_dir()
                {
                    std::fs::remove_dir_all(entry.path()).map_err(storage_error)?;
                }
            }
            Ok(ClearResult {
                epoch: state.manifest.epoch.clone(),
            })
        })
        .await
    }
}
fn valid_manifest(value: &Manifest) -> bool {
    value.version == 1
        && Uuid::parse_str(&value.epoch).is_ok()
        && value.entries.len() <= 200
        && value
            .entries
            .values()
            .map(|entry| entry.bytes as u128)
            .sum::<u128>()
            <= MAX_BYTES as u128
        && value.browse.len() <= 100
        && value
            .browse
            .iter()
            .all(|(key, value)| key == &value.programme_id && value.validate().is_ok())
        && value.entries.values().all(|entry| {
            entry
                .file
                .strip_suffix(".json")
                .is_some_and(|stem| Uuid::parse_str(stem).is_ok())
        })
}
fn load(owner: &Owner, state: &mut State, key: &str) -> Option<Snapshot> {
    if let Some(snapshot) = state.memory.get(key) {
        return Some(snapshot.clone());
    }
    let entry = state.manifest.entries.get(key)?;
    match read_json::<Snapshot>(
        &owner.root.join(&state.manifest.epoch).join(&entry.file),
        MAX_BYTES as u64,
    ) {
        Ok(Some(snapshot))
            if snapshot.validate().is_ok()
                && snapshot.payload.key().name().is_ok_and(|name| name == key) =>
        {
            Some(snapshot)
        }
        _ => {
            state.manifest.entries.remove(key);
            state.warning = Some("部分节目缓存已损坏，请刷新".into());
            None
        }
    }
}
fn commit(owner: &Owner, state: &mut State, next: &Manifest) -> Result<()> {
    write_json_atomic(&owner.root.join("manifest.json"), next).map_err(|error| {
        state.warning = Some(WARNING.into());
        AppError::with_source(ErrorCode::Storage, WARNING, error)
            .reported("save programme cache index")
    })
}
fn trim(manifest: &mut Manifest) {
    while manifest.entries.len() > 200
        || manifest
            .entries
            .values()
            .map(|entry| entry.bytes)
            .sum::<usize>()
            > MAX_BYTES
    {
        let oldest = manifest
            .entries
            .iter()
            .min_by_key(|(_, value)| value.accessed)
            .map(|(key, _)| key.clone())
            .unwrap();
        manifest.entries.remove(&oldest);
    }
}
fn cleanup_entries(owner: &Owner, old: &Manifest, next: &Manifest) {
    for entry in old.entries.values() {
        if !next.entries.values().any(|value| value.file == entry.file) {
            // The manifest is already committed; stale files are reconstructible
            // debris and a later clear retries their removal.
            let _ = std::fs::remove_file(owner.root.join(&old.epoch).join(&entry.file));
        }
    }
}
fn storage_error(error: std::io::Error) -> AppError {
    AppError::with_source(ErrorCode::Storage, "缓存清除未完成，请重试", error)
}
