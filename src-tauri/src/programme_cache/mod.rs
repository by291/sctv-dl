mod manifest;
mod models;
mod persistence;

pub use models::*;

use std::{
    collections::BTreeMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};

use chrono::{SecondsFormat, Utc};
use uuid::Uuid;

use crate::{
    error::{AppError, ErrorCode, Result},
    lifecycle::OperationGuard,
};

use manifest::Manifest;
use persistence::{CacheStorage, CommitOutcome, DiskRead};

const MAX_BYTES: usize = 20 * 1024 * 1024;
const WARNING: &str = "节目缓存无法保存到本地，当前数据仅在本次会话中保留";
const CORRUPT_INDEX: &str = "节目缓存索引已损坏，已开始新的缓存代际";
const CORRUPT_SNAPSHOT: &str = "部分节目缓存已损坏，请刷新";

enum SnapshotLoad {
    Found(Snapshot),
    Missing,
    Unavailable,
}

impl SnapshotLoad {
    fn readable(&self) -> bool {
        !matches!(self, Self::Unavailable)
    }

    fn snapshot(self) -> Option<Snapshot> {
        match self {
            Self::Found(snapshot) => Some(snapshot),
            Self::Missing | Self::Unavailable => None,
        }
    }
}

struct State {
    manifest: Manifest,
    memory: BTreeMap<String, Snapshot>,
    manifest_persisted: bool,
    warning: Option<String>,
}

impl State {
    fn snapshot_persisted(&self, storage: &CacheStorage, key: &str) -> bool {
        storage.writable() && self.manifest_persisted && !self.memory.contains_key(key)
    }

    fn remember(&mut self, key: String, snapshot: Snapshot) {
        self.memory.insert(key.clone(), snapshot);

        // Failed writes retain bounded process-local results without changing the
        // committed index. Prefer keeping the result of the current operation.
        while self.memory.len() > 200
            || self
                .memory
                .values()
                .map(|value| serde_json::to_vec(value).map_or(MAX_BYTES, |bytes| bytes.len()))
                .sum::<usize>()
                > MAX_BYTES
        {
            let oldest = self.memory.keys().find(|name| *name != &key).cloned();

            if let Some(oldest) = oldest {
                self.memory.remove(&oldest);
            } else {
                break;
            }
        }
    }
}

struct Owner {
    storage: CacheStorage,
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
            storage: CacheStorage::unavailable(),
            state: Mutex::new(State {
                manifest: Manifest::default(),
                memory: BTreeMap::new(),
                manifest_persisted: false,
                warning: Some(error.reported("open programme cache").message),
            }),
        }))
    }

    fn open_blocking(root: PathBuf) -> Self {
        let (mut storage, lock) = CacheStorage::open(root);
        let mut warning = lock
            .err()
            .map(|error| report_storage(error, WARNING, "lock programme cache").message);
        let manifest = match storage.read_manifest() {
            DiskRead::Found(manifest) => manifest,
            DiskRead::Missing => Manifest::default(),
            DiskRead::Corrupt(error) => {
                warning = Some(
                    report_storage(error, CORRUPT_INDEX, "read programme cache index").message,
                );
                Manifest::default()
            }
            DiskRead::Unavailable(error) => {
                storage.protect_unreadable_manifest();
                warning =
                    Some(report_storage(error, WARNING, "read programme cache index").message);
                Manifest::default()
            }
        };

        let mut state = State {
            manifest,
            memory: BTreeMap::new(),
            manifest_persisted: false,
            warning,
        };

        if storage.writable() {
            // Initialization keeps a corruption notice visible until a later
            // successful operation, even after publishing the fresh generation.
            let notice = state.warning.clone();
            let outcome = storage.commit_manifest(&state.manifest);
            let persisted = apply_commit_status(&mut state, outcome, "initialize programme cache");

            if persisted {
                state.warning = notice;
            }
        }

        Self(Arc::new(Owner {
            storage,
            state: Mutex::new(state),
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

            action(&owner, &mut state).map_err(|error| error.reported("update programme cache"))
        })
        .await
        .map_err(|error| {
            AppError::with_source(ErrorCode::Storage, WARNING, error)
                .reported("update programme cache")
        })?
    }

    pub async fn read(&self, key: CacheKey, operation: OperationGuard) -> Result<CacheRead> {
        let name = key.name()?;

        self.run(operation, move |owner, state| {
            let loaded = load(owner, state, &name);
            let readable = loaded.readable();
            let snapshot = loaded.snapshot();

            if snapshot.is_some() && owner.storage.writable() {
                let mut next = state.manifest.clone();
                next.touch(&name);
                commit_manifest(owner, state, next);
            }

            Ok(CacheRead {
                epoch: state.manifest.epoch.clone(),
                snapshot,
                persisted: readable && state.snapshot_persisted(&owner.storage, &name),
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
            let loaded = load(owner, state, &name);
            let readable = loaded.readable();
            let previous = loaded.snapshot();

            if expected_epoch != state.manifest.epoch {
                return Ok(CacheWriteResult {
                    epoch: state.manifest.epoch.clone(),
                    snapshot: previous,
                    accepted: false,
                    persisted: readable && state.snapshot_persisted(&owner.storage, &name),
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

            let persisted = save_snapshot(owner, state, &name, &snapshot, bytes);

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
                persisted: owner.storage.writable() && state.manifest_persisted,
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
                    persisted: owner.storage.writable() && state.manifest_persisted,
                });
            }

            let mut next = state.manifest.clone();
            next.insert_browse(value);
            let persisted = if owner.storage.writable() {
                let outcome = owner.storage.commit_manifest(&next);
                apply_commit_status(state, outcome, "save programme cache index")
            } else {
                false
            };

            // Browse state remains available in this process even if the write
            // failed before replacement; the next commit retries the full index.
            state.manifest = next;
            state.manifest_persisted = persisted;

            Ok(WriteResult {
                accepted: true,
                persisted,
            })
        })
        .await
    }

    pub async fn clear(&self, operation: OperationGuard) -> Result<ClearResult> {
        self.run(operation, |owner, state| {
            if !owner.storage.writable() {
                return Err(AppError::new(
                    ErrorCode::Storage,
                    "无法清除本地节目缓存，请重试",
                ));
            }

            let next = Manifest::default();
            let outcome = owner.storage.commit_manifest(&next);
            let applied = outcome.applied();

            if applied {
                // Replacement is the generation fence even when the final
                // directory sync fails. Never revive the previous generation.
                state.manifest = next;
                state.memory.clear();
            }

            match outcome {
                CommitOutcome::Durable => {
                    state.manifest_persisted = true;
                    state.warning = None;
                }
                CommitOutcome::Replaced(error) | CommitOutcome::Unchanged(error) => {
                    if applied {
                        state.manifest_persisted = false;
                    }

                    state.warning = Some(WARNING.into());
                    return Err(AppError::with_source(
                        ErrorCode::Storage,
                        "缓存清除未完成，请重试",
                        error,
                    ));
                }
            }

            owner
                .storage
                .cleanup_epochs(&state.manifest.epoch)
                .map_err(|error| {
                    AppError::with_source(ErrorCode::Storage, "缓存清除未完成，请重试", error)
                })?;

            Ok(ClearResult {
                epoch: state.manifest.epoch.clone(),
            })
        })
        .await
    }
}

fn load(owner: &Owner, state: &mut State, key: &str) -> SnapshotLoad {
    if let Some(snapshot) = state.memory.get(key) {
        return SnapshotLoad::Found(snapshot.clone());
    }

    match owner.storage.read_snapshot(&state.manifest, key) {
        DiskRead::Found(snapshot) => SnapshotLoad::Found(snapshot),
        DiskRead::Missing => {
            state.manifest.entries.remove(key);
            SnapshotLoad::Missing
        }
        DiskRead::Corrupt(error) => {
            state.manifest.entries.remove(key);
            state.warning = Some(
                report_storage(error, CORRUPT_SNAPSHOT, "read programme cache snapshot").message,
            );
            SnapshotLoad::Missing
        }
        DiskRead::Unavailable(error) => {
            // An I/O failure does not prove that the referenced file is invalid.
            // Keep its index entry so a later read can recover without refetching.
            state.warning =
                Some(report_storage(error, WARNING, "read programme cache snapshot").message);
            SnapshotLoad::Unavailable
        }
    }
}

fn save_snapshot(
    owner: &Owner,
    state: &mut State,
    key: &str,
    snapshot: &Snapshot,
    bytes: usize,
) -> bool {
    if !owner.storage.writable() {
        state.remember(key.into(), snapshot.clone());
        state.warning = Some(WARNING.into());
        return false;
    }

    let mut next = state.manifest.clone();
    next.insert_snapshot(key.into(), format!("{}.json", Uuid::new_v4()), bytes);
    let outcome = owner.storage.commit_snapshot(&next, key, snapshot);

    if outcome.applied() {
        owner.storage.cleanup_entries(&state.manifest, &next);
        state.manifest = next;
        state.memory.remove(key);
    } else {
        state.remember(key.into(), snapshot.clone());
    }

    apply_commit_status(state, outcome, "write programme cache")
}

fn commit_manifest(owner: &Owner, state: &mut State, next: Manifest) -> bool {
    let outcome = owner.storage.commit_manifest(&next);

    if outcome.applied() {
        state.manifest = next;
    }

    apply_commit_status(state, outcome, "save programme cache index")
}

fn apply_commit_status(state: &mut State, outcome: CommitOutcome, context: &str) -> bool {
    match outcome {
        CommitOutcome::Durable => {
            state.manifest_persisted = true;
            state.warning = (!state.memory.is_empty()).then(|| WARNING.into());
            true
        }
        CommitOutcome::Replaced(error) => {
            state.manifest_persisted = false;
            state.warning = Some(report_storage(error, WARNING, context).message);
            false
        }
        CommitOutcome::Unchanged(error) => {
            // Discarded candidates cannot change the retained index's durability.
            // Browse writes explicitly mark their adopted candidate memory-only.
            state.warning = Some(report_storage(error, WARNING, context).message);
            false
        }
    }
}

fn report_storage(error: std::io::Error, message: &str, context: &str) -> AppError {
    AppError::with_source(ErrorCode::Storage, message, error).reported(context)
}
