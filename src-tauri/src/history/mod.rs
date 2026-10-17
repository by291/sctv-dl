mod models;
pub use models::*;

use chrono::{SecondsFormat, Utc};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    fs::{File, OpenOptions},
    path::PathBuf,
    sync::{Arc, Mutex},
};
use uuid::Uuid;

use crate::{
    error::{AppError, ErrorCode, Result},
    lifecycle::OperationGuard,
    storage::{read_json, replacement_committed, write_json_atomic},
};

const MAX_DOCUMENT_BYTES: u64 = 8 * 1024 * 1024;
type Listener = Arc<dyn Fn(HistorySnapshot) -> bool + Send + Sync>;

#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Document {
    version: u32,
    revision: u64,
    entries: Vec<HistoryEntry>,
}

#[derive(Clone)]
struct Session {
    metadata: HistoryMetadata,
    sequence: u64,
}

#[derive(Clone)]
struct State {
    document: Document,
    sessions: HashMap<String, Session>,
    persisted: bool,
    warning: Option<String>,
}

struct Owner {
    path: PathBuf,
    // The OS lock lives as long as the owner, including detached blocking workers.
    _process_lock: Option<File>,
    writable: bool,
    writes: Mutex<()>,
    state: Mutex<State>,
    listeners: Mutex<HashMap<String, Listener>>,
}

/// Owns durable entries and process-local session tokens. Every mutation worker
/// retains its exit guard and writer gate until persistence and publication finish.
#[derive(Clone)]
pub struct HistoryService(Arc<Owner>);

impl HistoryService {
    pub async fn open(path: PathBuf) -> Self {
        match tokio::task::spawn_blocking(move || Self::open_blocking(path)).await {
            Ok(service) => service,
            Err(error) => Self::unavailable(AppError::with_source(
                ErrorCode::Storage,
                "无法读取观看记录，本次记录仅在当前会话保存",
                error,
            )),
        }
    }

    pub fn unavailable(error: AppError) -> Self {
        let warning = error.reported("open history").message;
        Self::from_parts(
            PathBuf::new(),
            None,
            Document {
                version: 1,
                ..Default::default()
            },
            Some(warning),
        )
    }

    fn open_blocking(path: PathBuf) -> Self {
        let lock = (|| -> std::io::Result<File> {
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            let lock = OpenOptions::new()
                .create(true)
                .truncate(false)
                .read(true)
                .write(true)
                .open(path.with_extension("lock"))?;
            lock.try_lock().map_err(std::io::Error::other)?;
            Ok(lock)
        })();
        let (lock, mut warning) = match lock {
            Ok(lock) => (Some(lock), None),
            Err(error) => (
                None,
                Some(
                    AppError::with_source(
                        ErrorCode::Storage,
                        "观看记录存储不可用或正由另一进程使用，本次记录仅在当前会话保存",
                        error,
                    )
                    .reported("lock history")
                    .message,
                ),
            ),
        };
        let document = read_json::<Document>(&path, MAX_DOCUMENT_BYTES).and_then(|document| {
            let document = document.unwrap_or(Document {
                version: 1,
                ..Default::default()
            });
            validate_document(&document)?;
            Ok(document)
        });
        let document = match document {
            Ok(document) => document,
            Err(error) => {
                warning = Some(
                    AppError::with_source(
                        ErrorCode::Storage,
                        "观看记录文件无法读取，原文件已保留，本次记录仅在当前会话保存",
                        error,
                    )
                    .reported("read history")
                    .message,
                );
                Document {
                    version: 1,
                    ..Default::default()
                }
            }
        };
        Self::from_parts(path, lock, document, warning)
    }

    fn from_parts(
        path: PathBuf,
        lock: Option<File>,
        document: Document,
        warning: Option<String>,
    ) -> Self {
        let writable = warning.is_none();
        Self(Arc::new(Owner {
            path,
            _process_lock: lock,
            writable,
            writes: Mutex::new(()),
            state: Mutex::new(State {
                document,
                sessions: HashMap::new(),
                persisted: writable,
                warning,
            }),
            listeners: Mutex::default(),
        }))
    }

    pub fn list(&self) -> HistorySnapshot {
        snapshot(&self.0.state.lock().unwrap())
    }

    pub fn subscribe(
        &self,
        listener: impl Fn(HistorySnapshot) -> bool + Send + Sync + 'static,
    ) -> String {
        let id = Uuid::new_v4().to_string();
        self.0
            .listeners
            .lock()
            .unwrap()
            .insert(id.clone(), Arc::new(listener));
        id
    }

    pub fn unsubscribe(&self, id: &str) {
        self.0.listeners.lock().unwrap().remove(id);
    }

    pub async fn begin(
        &self,
        metadata: HistoryMetadata,
        guard: OperationGuard,
    ) -> Result<HistorySession> {
        self.blocking(guard, move |owner| {
            metadata.validate()?;
            let mut state = owner.state.lock().unwrap();
            let entry = state
                .document
                .entries
                .iter()
                .find(|entry| entry.metadata.content == metadata.content)
                .cloned();
            // Opening metadata never resets a saved resume point. Replacing the
            // previous token immediately makes delayed older samples harmless.
            state
                .sessions
                .retain(|_, session| session.metadata.content != metadata.content);
            let id = Uuid::new_v4().to_string();
            state.sessions.insert(
                id.clone(),
                Session {
                    metadata,
                    sequence: 0,
                },
            );
            Ok(HistorySession { id, entry })
        })
        .await
    }

    pub async fn record(
        &self,
        id: String,
        sample: HistorySample,
        guard: OperationGuard,
    ) -> Result<RecordResult> {
        self.blocking(guard, move |owner| {
            sample.validate()?;
            let mut next = owner.state.lock().unwrap().clone();
            let Some(session) = next.sessions.get_mut(&id) else {
                return Ok(RecordResult {
                    accepted: false,
                    persisted: next.persisted,
                });
            };
            if sample.sequence <= session.sequence {
                // A post-replacement sync failure already consumed this sequence.
                // Retrying it can establish durability without accepting an old
                // observation or changing the document's current progress.
                if sample.sequence == session.sequence && !next.persisted && owner.writable {
                    commit(owner, next)?;
                }
                return Ok(RecordResult {
                    accepted: false,
                    persisted: owner.state.lock().unwrap().persisted,
                });
            }
            session.sequence = sample.sequence;
            let entry = HistoryEntry {
                metadata: session.metadata.clone(),
                position_ms: sample.position_ms,
                duration_ms: sample.duration_ms,
                viewed_at: Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true),
                completed: sample.completed(),
            };
            next.document
                .entries
                .retain(|old| old.metadata.content != entry.metadata.content);
            next.document.entries.insert(0, entry);
            next.document.entries.truncate(500);
            commit(owner, next)?;
            Ok(RecordResult {
                accepted: true,
                persisted: owner.state.lock().unwrap().persisted,
            })
        })
        .await
    }

    pub async fn end(&self, id: String, guard: OperationGuard) -> Result<()> {
        self.blocking(guard, move |owner| {
            owner.state.lock().unwrap().sessions.remove(&id);
            Ok(())
        })
        .await
    }

    pub async fn remove(&self, content: ContentRef, guard: OperationGuard) -> Result<()> {
        self.blocking(guard, move |owner| {
            let mut next = owner.state.lock().unwrap().clone();
            next.sessions
                .retain(|_, session| session.metadata.content != content);
            next.document
                .entries
                .retain(|entry| entry.metadata.content != content);
            commit(owner, next)
        })
        .await
    }

    pub async fn clear(&self, guard: OperationGuard) -> Result<()> {
        self.blocking(guard, move |owner| {
            let mut next = owner.state.lock().unwrap().clone();
            next.sessions.clear();
            next.document.entries.clear();
            commit(owner, next)
        })
        .await
    }

    async fn blocking<T: Send + 'static>(
        &self,
        guard: OperationGuard,
        action: impl FnOnce(&Owner) -> Result<T> + Send + 'static,
    ) -> Result<T> {
        let owner = self.0.clone();
        tokio::task::spawn_blocking(move || {
            let _operation = guard;
            let _writer = owner.writes.lock().unwrap();
            action(&owner).map_err(|error| error.reported("update history"))
        })
        .await
        .map_err(|error| {
            AppError::with_source(ErrorCode::Storage, "观看记录操作异常终止", error)
                .reported("update history")
        })?
    }
}

fn snapshot(state: &State) -> HistorySnapshot {
    HistorySnapshot {
        entries: state.document.entries.clone(),
        revision: state.document.revision,
        persisted: state.persisted,
        warning: state.warning.clone(),
    }
}

fn publish(owner: &Owner) {
    let current = snapshot(&owner.state.lock().unwrap());
    let listeners: Vec<_> = owner
        .listeners
        .lock()
        .unwrap()
        .iter()
        .map(|(id, listener)| (id.clone(), listener.clone()))
        .collect();
    for (id, listener) in listeners {
        if !listener(current.clone()) {
            owner.listeners.lock().unwrap().remove(&id);
        }
    }
}

fn commit(owner: &Owner, mut next: State) -> Result<()> {
    next.document.revision += 1;
    if owner.writable {
        let result = serde_json::to_vec(&next.document)
            .map_err(std::io::Error::other)
            .and_then(|bytes| {
                if bytes.len() as u64 > MAX_DOCUMENT_BYTES {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        "History document exceeds its size limit",
                    ));
                }
                write_json_atomic(&owner.path, &next.document)
            });
        if let Err(error) = result {
            let replaced = replacement_committed(&error);
            let error =
                AppError::with_source(ErrorCode::Storage, "观看记录保存失败，请重试", error);
            {
                let mut state = owner.state.lock().unwrap();
                if replaced {
                    // The rename committed entries and token invalidation even
                    // though directory synchronization could not prove durability.
                    *state = next;
                } else {
                    state.document.revision += 1;
                }
                state.persisted = false;
                state.warning = Some(error.message.clone());
            }
            publish(owner);
            return Err(error);
        }
        next.persisted = true;
        next.warning = None;
    }
    *owner.state.lock().unwrap() = next;
    publish(owner);
    Ok(())
}

fn validate_document(document: &Document) -> std::io::Result<()> {
    let valid = document.version == 1
        && document.entries.len() <= 500
        && document.revision < 9_007_199_254_740_991;
    if !valid {
        return Err(std::io::Error::other("Invalid history document"));
    }
    let mut keys = std::collections::HashSet::new();
    for entry in &document.entries {
        entry.metadata.validate().map_err(std::io::Error::other)?;
        HistorySample {
            position_ms: entry.position_ms,
            duration_ms: entry.duration_ms,
            ended: entry.completed,
            sequence: 1,
        }
        .validate()
        .map_err(std::io::Error::other)?;
        let content = &entry.metadata.content;
        if !keys.insert((&content.programme_id, &content.date_id, &content.content_id))
            || !entry.viewed_at.ends_with('Z')
            || chrono::DateTime::parse_from_rfc3339(&entry.viewed_at).is_err()
        {
            return Err(std::io::Error::other("Invalid history entry"));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests;
