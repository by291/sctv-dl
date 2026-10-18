use std::{
    collections::HashMap,
    path::Path,
    sync::{Arc, Mutex},
};

use uuid::Uuid;

use super::{
    manager::{Control, TRANSFER_CONCURRENCY},
    store::{self, DownloadDocument, DownloadStore, StoredTask},
    *,
};
use crate::error::{AppError, ErrorCode, Result};

struct Entry {
    stored: StoredTask,
    control: Arc<Control>,
}

struct State {
    accepting: bool,
    entries: Vec<Entry>,
    revision: u64,
}

type Listener = Arc<dyn Fn(DownloadTask) -> bool + Send + Sync>;
type EventListener = Arc<dyn Fn(DownloadEvent) -> bool + Send + Sync>;

pub(super) enum Admission {
    Available,
    Duplicate(String),
}

/// Owns task state, durable writes and revisioned notifications. Callers never borrow its locks.
pub(super) struct TaskRecords {
    state: Mutex<State>,
    writes: Mutex<()>,
    store: Result<Option<DownloadStore>>,
    epoch: String,
    listeners: Mutex<HashMap<String, Listener>>,
    event_listeners: Mutex<HashMap<String, EventListener>>,
    #[cfg(test)]
    pub(super) before_save: Mutex<Option<Box<dyn FnOnce() + Send>>>,
}

impl TaskRecords {
    pub fn new(store: Result<Option<DownloadStore>>, document: DownloadDocument) -> Self {
        Self {
            state: Mutex::new(State {
                accepting: true,
                entries: document
                    .tasks
                    .into_iter()
                    .map(|stored| Entry {
                        stored,
                        control: Control::new(true),
                    })
                    .collect(),
                revision: document.revision,
            }),
            writes: Mutex::new(()),
            store,
            epoch: Uuid::new_v4().to_string(),
            listeners: Mutex::default(),
            event_listeners: Mutex::default(),
            #[cfg(test)]
            before_save: Mutex::new(None),
        }
    }

    pub fn durable(&self) -> bool {
        matches!(&self.store, Ok(Some(_)))
    }

    pub fn accepting(&self) -> bool {
        self.state.lock().unwrap().accepting
    }

    pub fn set_accepting(&self, accepting: bool) {
        self.state.lock().unwrap().accepting = accepting;
    }

    pub fn records(&self) -> Vec<StoredTask> {
        self.state
            .lock()
            .unwrap()
            .entries
            .iter()
            .map(|entry| entry.stored.clone())
            .collect()
    }

    pub fn list(&self) -> Vec<DownloadTask> {
        self.records()
            .into_iter()
            .map(|record| record.task)
            .collect()
    }

    pub fn snapshot(&self) -> Result<DownloadSnapshot> {
        self.available()?;

        let state = self.state.lock().unwrap();
        Ok(DownloadSnapshot {
            epoch: self.epoch.clone(),
            revision: state.revision,
            tasks: state
                .entries
                .iter()
                .map(|entry| entry.stored.task.clone())
                .collect(),
        })
    }

    pub fn find(&self, id: &str, attempt: Option<&str>) -> Option<(StoredTask, Arc<Control>)> {
        self.state
            .lock()
            .unwrap()
            .entries
            .iter()
            .find(|entry| {
                entry.stored.task.id == id
                    && attempt.is_none_or(|attempt| entry.stored.task.attempt_id == attempt)
            })
            .map(|entry| (entry.stored.clone(), entry.control.clone()))
    }

    pub fn active_controls(&self) -> Vec<Arc<Control>> {
        self.state
            .lock()
            .unwrap()
            .entries
            .iter()
            .filter(|entry| entry.stored.task.active())
            .map(|entry| entry.control.clone())
            .collect()
    }

    pub fn checkpoint_failed(&self) -> bool {
        self.state.lock().unwrap().entries.iter().any(|entry| {
            entry
                .control
                .checkpoint_failed
                .load(std::sync::atomic::Ordering::SeqCst)
        })
    }

    pub fn replace_control(&self, id: &str, control: Arc<Control>) {
        if let Some(entry) = self
            .state
            .lock()
            .unwrap()
            .entries
            .iter_mut()
            .find(|entry| entry.stored.task.id == id)
        {
            entry.control = control;
        }
    }

    pub fn subscribe(
        &self,
        listener: impl Fn(DownloadTask) -> bool + Send + Sync + 'static,
    ) -> String {
        let id = Uuid::new_v4().to_string();
        self.listeners
            .lock()
            .unwrap()
            .insert(id.clone(), Arc::new(listener));
        id
    }

    pub fn unsubscribe(&self, id: &str) {
        self.listeners.lock().unwrap().remove(id);
    }

    pub fn subscribe_events(
        &self,
        listener: impl Fn(DownloadEvent) -> bool + Send + Sync + 'static,
    ) -> Result<String> {
        self.available()?;

        let id = Uuid::new_v4().to_string();
        self.event_listeners
            .lock()
            .unwrap()
            .insert(id.clone(), Arc::new(listener));
        Ok(id)
    }

    pub fn unsubscribe_events(&self, id: &str) {
        self.event_listeners.lock().unwrap().remove(id);
    }

    pub fn admission(
        &self,
        file: &PreparedDownload,
        directory: &Path,
        retry: Option<&str>,
        capacity: usize,
    ) -> Result<Admission> {
        let state = self.state.lock().unwrap();
        if !state.accepting {
            return Err(AppError::new(
                ErrorCode::Cancelled,
                "应用正在退出，无法操作下载",
            ));
        }

        let unfinished: Vec<_> = state
            .entries
            .iter()
            .filter(|entry| {
                entry.stored.task.unfinished() && Some(entry.stored.task.id.as_str()) != retry
            })
            .collect();
        if let Some(entry) = unfinished.iter().find(|entry| {
            entry.stored.task.content == file.content
                && entry.stored.task.quality == file.quality
                && entry.stored.directory == directory
        }) {
            return Ok(Admission::Duplicate(entry.stored.task.id.clone()));
        }

        if unfinished.len() >= capacity + TRANSFER_CONCURRENCY {
            return Err(AppError::new(
                ErrorCode::InvalidInput,
                "下载队列已满，请稍后重试",
            ));
        }
        Ok(Admission::Available)
    }

    pub fn insert(&self, mut stored: StoredTask) -> Result<Arc<Control>> {
        let _writer = self.writes.lock().unwrap();
        let (mut records, revision) = self.next_document();
        records.push(stored.clone());

        let persisted = self.save(records, revision);
        if let Err(error) = &persisted
            && !store::replacement_committed(error)
        {
            return Err(error.clone());
        }

        // A replaced index already owns the reservation even when directory sync fails.
        // Keep a settled failed entry so neither dispatch nor cleanup can discard that ownership.
        let control = Control::new(persisted.is_err());
        if let Err(error) = &persisted {
            stored.task.state = TaskState::Failed;
            stored.task.error = Some(error.message.clone());
            control
                .checkpoint_failed
                .store(true, std::sync::atomic::Ordering::SeqCst);
        }

        let task = stored.task.clone();

        let revision = {
            let mut state = self.state.lock().unwrap();
            state.entries.push(Entry {
                stored,
                control: control.clone(),
            });
            state.revision += 1;
            state.revision
        };

        self.emit(task, revision);
        persisted?;
        Ok(control)
    }

    pub fn remove(&self, id: &str) -> Result<()> {
        let _writer = self.writes.lock().unwrap();
        let (mut records, revision) = self.next_document();
        records.retain(|record| record.task.id != id);

        let persisted = self.save(records, revision);
        if let Err(error) = &persisted
            && !store::replacement_committed(error)
        {
            return Err(error.clone());
        }

        let revision = {
            let mut state = self.state.lock().unwrap();
            state.entries.retain(|entry| entry.stored.task.id != id);
            state.revision += 1;
            state.revision
        };

        self.emit_event(DownloadEvent::Remove {
            epoch: self.epoch.clone(),
            revision,
            task_id: id.into(),
        });
        persisted
    }

    fn next_document(&self) -> (Vec<StoredTask>, u64) {
        let state = self.state.lock().unwrap();
        (
            state
                .entries
                .iter()
                .map(|entry| entry.stored.clone())
                .collect(),
            state.revision + 1,
        )
    }

    pub fn available(&self) -> Result<()> {
        self.store.as_ref().map(|_| ()).map_err(Clone::clone)
    }

    fn emit_event(&self, event: DownloadEvent) {
        let listeners: Vec<_> = self
            .event_listeners
            .lock()
            .unwrap()
            .iter()
            .map(|(id, listener)| (id.clone(), listener.clone()))
            .collect();

        for (id, listener) in listeners {
            if !listener(event.clone()) {
                self.event_listeners.lock().unwrap().remove(&id);
            }
        }
    }

    fn emit(&self, task: DownloadTask, revision: u64) {
        self.emit_event(DownloadEvent::Upsert {
            epoch: self.epoch.clone(),
            revision,
            task: Box::new(task.clone()),
        });
        let listeners: Vec<_> = self
            .listeners
            .lock()
            .unwrap()
            .iter()
            .map(|(id, listener)| (id.clone(), listener.clone()))
            .collect();

        for (id, listener) in listeners {
            if !listener(task.clone()) {
                self.listeners.lock().unwrap().remove(&id);
            }
        }
    }

    fn save(&self, tasks: Vec<StoredTask>, revision: u64) -> Result<()> {
        #[cfg(test)]
        if let Some(before_save) = self.before_save.lock().unwrap().take() {
            before_save();
        }

        if let Some(store) = self.store.as_ref().map_err(Clone::clone)? {
            store.save(&DownloadDocument {
                version: 1,
                revision,
                tasks,
            })?;
        }
        Ok(())
    }

    pub async fn change(
        self: &Arc<Self>,
        id: String,
        attempt: String,
        update: impl FnOnce(&mut StoredTask) + Send + 'static,
    ) -> Result<Option<DownloadTask>> {
        let owner = self.clone();
        tokio::task::spawn_blocking(move || owner.change_blocking(&id, &attempt, update))
            .await
            .map_err(|error| {
                AppError::with_source(ErrorCode::Storage, "下载记录更新异常终止", error)
            })?
    }

    pub fn change_blocking(
        &self,
        id: &str,
        attempt: &str,
        update: impl FnOnce(&mut StoredTask),
    ) -> Result<Option<DownloadTask>> {
        self.try_change_blocking(id, attempt, |record| {
            update(record);
            Ok(())
        })
    }

    pub fn try_change_blocking(
        &self,
        id: &str,
        attempt: &str,
        update: impl FnOnce(&mut StoredTask) -> Result<()>,
    ) -> Result<Option<DownloadTask>> {
        let _writer = self.writes.lock().unwrap();
        let (mut records, revision) = self.next_document();
        let Some(record) = records
            .iter_mut()
            .find(|record| record.task.id == id && record.task.attempt_id == attempt)
        else {
            return Ok(None);
        };

        update(record)?;
        record.task.revision += 1;
        let mut updated = record.clone();

        let persisted = self.save(records, revision);
        if persisted.is_err()
            && let Some(entry) = self
                .state
                .lock()
                .unwrap()
                .entries
                .iter()
                .find(|entry| entry.stored.task.id == id)
        {
            entry
                .control
                .checkpoint_failed
                .store(true, std::sync::atomic::Ordering::SeqCst);
        }
        if let Err(error) = &persisted
            && !store::replacement_committed(error)
        {
            return Err(error.clone());
        }

        let revision = {
            let mut state = self.state.lock().unwrap();
            let Some(entry) = state.entries.iter_mut().find(|entry| {
                entry.stored.task.id == id && entry.stored.task.attempt_id == attempt
            }) else {
                return Ok(None);
            };

            // Progress can advance during disk I/O; commit after its latest in-memory revision.
            updated.task.revision = updated.task.revision.max(entry.stored.task.revision + 1);
            entry.stored = updated.clone();
            entry
                .control
                .checkpoint_failed
                .store(persisted.is_err(), std::sync::atomic::Ordering::SeqCst);
            state.revision += 1;
            state.revision
        };

        self.emit(updated.task.clone(), revision);
        persisted?;
        Ok(Some(updated.task))
    }

    pub fn progress(
        &self,
        id: &str,
        attempt: &str,
        received: u64,
        total: Option<u64>,
        publish: bool,
    ) {
        let changed = {
            let mut state = self.state.lock().unwrap();
            let Some(entry) = state.entries.iter_mut().find(|entry| {
                entry.stored.task.id == id
                    && entry.stored.task.attempt_id == attempt
                    && entry.stored.task.active()
            }) else {
                return;
            };
            entry.stored.task.received_bytes = received;
            entry.stored.task.total_bytes = total;
            entry.stored.task.revision += 1;
            let task = entry.stored.task.clone();
            state.revision += 1;
            (task, state.revision)
        };

        if publish {
            self.emit(changed.0, changed.1);
        }
    }

    pub fn report_failure(&self, id: &str, attempt: &str, error: AppError) {
        let error = error.reported("download task");
        let changed = {
            let mut state = self.state.lock().unwrap();
            let Some(entry) = state.entries.iter_mut().find(|entry| {
                entry.stored.task.id == id && entry.stored.task.attempt_id == attempt
            }) else {
                return;
            };
            if error.code == ErrorCode::Storage {
                entry
                    .control
                    .checkpoint_failed
                    .store(true, std::sync::atomic::Ordering::SeqCst);
            }
            entry.stored.task.state = TaskState::Failed;
            entry.stored.task.error = Some(error.message);
            entry.stored.task.revision += 1;
            let task = entry.stored.task.clone();
            state.revision += 1;
            (task, state.revision)
        };

        self.emit(changed.0, changed.1);
    }

    pub(super) fn request_stop(&self, id: &str, attempt: &str, intent: StopIntent) -> bool {
        // Serialize the stop decision with the worker's finalization transition.
        let _writer = self.writes.lock().unwrap();
        let changed = {
            let mut state = self.state.lock().unwrap();
            let Some(entry) = state.entries.iter_mut().find(|entry| {
                entry.stored.task.id == id
                    && entry.stored.task.attempt_id == attempt
                    && matches!(
                        entry.stored.task.state,
                        TaskState::Queued | TaskState::Running
                    )
            }) else {
                return false;
            };
            entry.control.stop(intent);
            if intent == StopIntent::Pause {
                entry.stored.task.state = TaskState::Pausing;
            }
            entry.stored.task.revision += 1;
            let task = entry.stored.task.clone();
            state.revision += 1;
            (task, state.revision)
        };

        self.emit(changed.0, changed.1);
        true
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::super::{files::DownloadDirectory, manager::DownloadManager};
    use super::*;

    fn source(content_id: &str) -> PreparedDownload {
        let content = ContentRef {
            programme_id: "1".into(),
            date_id: "2".into(),
            content_id: content_id.into(),
        };
        PreparedDownload {
            metadata: crate::history::HistoryMetadata {
                content: content.clone(),
                programme_name: "News".into(),
                broadcast_date: "2026-10-17".into(),
                title: "Clip".into(),
                cover: None,
            },
            content,
            filename: "clip.mp4".into(),
            quality: crate::media::Quality::Standard,
            url: "https://fscgc.scgchc.com/clip.mp4".into(),
        }
    }

    fn stored(path: &Path, content_id: &str, state: TaskState) -> StoredTask {
        let source = source(content_id);
        StoredTask {
            directory: path.to_owned(),
            reservation: None,
            completed_identity: None,
            task: DownloadTask {
                id: Uuid::new_v4().to_string(),
                attempt_id: Uuid::new_v4().to_string(),
                content: source.content,
                metadata: source.metadata,
                filename: source.filename,
                quality: source.quality,
                state,
                received_bytes: 0,
                total_bytes: None,
                error: None,
                revision: 1,
                created_at: "2026-10-17T00:00:00.000Z".into(),
                can_resume: false,
                has_partial: false,
                file_available: false,
            },
        }
    }

    #[cfg(unix)]
    #[test]
    fn insert_update_and_remove_follow_the_actual_disk_commit_phase() {
        use std::os::unix::fs::PermissionsExt;

        for operation in ["insert", "update", "remove"] {
            for committed in [false, true] {
                let root = tempfile::tempdir().unwrap();
                let index_directory = root.path().join("index");
                std::fs::create_dir(&index_directory).unwrap();
                let path = index_directory.join("downloads.json");
                let original = stored(root.path(), "3", TaskState::Cancelled);
                let incoming = stored(root.path(), "4", TaskState::Queued);
                let document = DownloadDocument {
                    version: 1,
                    revision: 1,
                    tasks: vec![original.clone()],
                };
                let store = DownloadStore::open(path.clone()).unwrap();
                store.save(&document).unwrap();
                let owner = TaskRecords::new(Ok(Some(store)), document);
                let events = Arc::new(Mutex::new(Vec::new()));
                let observed = events.clone();
                owner
                    .subscribe_events(move |event| {
                        observed.lock().unwrap().push(event);
                        true
                    })
                    .unwrap();

                // Write/search permits replacement; denying read makes the final parent sync fail.
                std::fs::set_permissions(
                    &index_directory,
                    std::fs::Permissions::from_mode(if committed { 0o300 } else { 0o500 }),
                )
                .unwrap();
                let outcome = match operation {
                    "insert" => owner.insert(incoming.clone()).map(|_| ()),
                    "update" => owner
                        .change_blocking(&original.task.id, &original.task.attempt_id, |record| {
                            record.task.state = TaskState::Missing
                        })
                        .map(|_| ()),
                    "remove" => owner.remove(&original.task.id),
                    _ => unreachable!(),
                };
                std::fs::set_permissions(&index_directory, std::fs::Permissions::from_mode(0o700))
                    .unwrap();

                let error = outcome.unwrap_err();
                assert_eq!(
                    store::replacement_committed(&error),
                    committed,
                    "{operation}"
                );
                let disk = DownloadStore::load(&path).unwrap();
                let current = owner.list();
                match operation {
                    "insert" => {
                        assert_eq!(disk.tasks.len(), if committed { 2 } else { 1 });
                        assert_eq!(current.len(), disk.tasks.len());
                        if committed {
                            assert_eq!(current[1].state, TaskState::Failed);
                        }
                    }
                    "update" => {
                        let expected = if committed {
                            TaskState::Missing
                        } else {
                            TaskState::Cancelled
                        };
                        assert_eq!(disk.tasks[0].task.state, expected);
                        assert_eq!(current[0].state, expected);
                    }
                    "remove" => {
                        assert_eq!(disk.tasks.len(), if committed { 0 } else { 1 });
                        assert_eq!(current.len(), disk.tasks.len());
                    }
                    _ => unreachable!(),
                }
                assert_eq!(events.lock().unwrap().len(), usize::from(committed));
                assert_eq!(
                    owner.snapshot().unwrap().revision,
                    if committed { 2 } else { 1 }
                );
            }
        }
    }

    #[tokio::test]
    async fn failed_attempt_and_rollback_retain_both_causes_and_owned_artifacts() {
        use std::error::Error;

        let root = tempfile::tempdir().unwrap();
        let directory = DownloadDirectory::open(root.path()).unwrap();
        let mut record = stored(directory.path(), "3", TaskState::Paused);
        let (writer, mut reservation) = directory.reserve("clip.mp4").unwrap();
        drop(writer);
        let journal = reservation
            .upgrade(record.task.id.clone(), record.task.attempt_id.clone())
            .unwrap();
        record.reservation = Some(journal.clone());
        record.task.can_resume = true;
        record.task.has_partial = true;
        reservation.retain();

        let manager = DownloadManager::build(
            Default::default(),
            Ok(None),
            DownloadDocument {
                version: 1,
                revision: 1,
                tasks: vec![record.clone()],
            },
        )
        .unwrap();
        manager
            .inner
            .directories
            .lock()
            .unwrap()
            .insert(directory.path().to_owned(), directory.clone());
        super::super::files::RECORD_WRITE_HOOK.with(|hook| {
            *hook.borrow_mut() = Some(Box::new(|path| {
                std::fs::remove_file(path).unwrap();
                std::fs::create_dir(path).unwrap();
            }));
        });

        let error = manager
            .inner
            .restart(
                DownloadActionRequest {
                    task_id: record.task.id.clone(),
                    attempt_id: record.task.attempt_id.clone(),
                    action: DownloadAction::Resume,
                },
                Some(source("3")),
                record.clone(),
            )
            .unwrap_err();
        let diagnostic = error.source().unwrap().to_string();
        assert!(
            diagnostic.contains("rollback"),
            "missing rollback cause: {diagnostic}"
        );
        assert!(
            diagnostic.contains("primary"),
            "missing primary cause: {diagnostic}"
        );
        assert_eq!(manager.list()[0].attempt_id, record.task.attempt_id);

        let partial = root.path().join(format!(".sctv-dl-{}.part", journal.id));
        assert!(partial.is_file());
        std::fs::remove_file(&partial).unwrap();
        std::fs::write(&partial, b"replacement").unwrap();
        assert!(directory.recover_reservation(&journal).is_err());
        assert_eq!(std::fs::read(partial).unwrap(), b"replacement");
        manager.shutdown().await;
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn admission_and_removal_events_follow_progress_during_disk_commit() {
        for remove in [false, true] {
            let root = tempfile::tempdir().unwrap();
            let running = stored(root.path(), "3", TaskState::Running);
            let removable = stored(root.path(), "4", TaskState::Cancelled);
            let manager = Arc::new(
                DownloadManager::build(
                    DownloadConfig::default(),
                    Ok(None),
                    DownloadDocument {
                        version: 1,
                        revision: 10,
                        tasks: vec![running.clone(), removable.clone()],
                    },
                )
                .unwrap(),
            );
            let _slots = manager
                .inner
                .slots
                .clone()
                .acquire_many_owned(2)
                .await
                .unwrap();
            let (entered_tx, entered_rx) = tokio::sync::oneshot::channel();
            let (release_tx, release_rx) = std::sync::mpsc::channel();
            *manager.inner.records.before_save.lock().unwrap() = Some(Box::new(move || {
                entered_tx.send(()).unwrap();
                release_rx.recv().unwrap();
            }));
            let events = Arc::new(Mutex::new(Vec::new()));
            let observed = events.clone();
            manager
                .subscribe_events(move |event| {
                    observed.lock().unwrap().push(event);
                    true
                })
                .unwrap();
            let owner = manager.clone();
            let path = root.path().to_owned();
            let work = tokio::spawn(async move {
                if remove {
                    let gate = crate::lifecycle::ExitController::default();
                    owner
                        .act(
                            DownloadActionRequest {
                                task_id: removable.task.id,
                                attempt_id: removable.task.attempt_id,
                                action: DownloadAction::Remove,
                            },
                            None,
                            Arc::new(gate.enter().await.unwrap()),
                        )
                        .await
                        .unwrap();
                } else {
                    owner.start(vec![source("5")], &path).await.unwrap();
                }
            });
            entered_rx.await.unwrap();
            for bytes in [10, 20, 30] {
                manager.inner.records.progress(
                    &running.task.id,
                    &running.task.attempt_id,
                    bytes,
                    Some(100),
                    true,
                );
            }
            let during_save = manager.snapshot().unwrap();
            release_tx.send(()).unwrap();
            work.await.unwrap();
            let after = manager.snapshot().unwrap();
            assert!(after.revision > during_save.revision);
            let event_revision = match events.lock().unwrap().last().unwrap() {
                DownloadEvent::Upsert { revision, .. } | DownloadEvent::Remove { revision, .. } => {
                    *revision
                }
            };
            assert!(event_revision > during_save.revision);
            assert_eq!(
                after
                    .tasks
                    .iter()
                    .find(|task| task.id == running.task.id)
                    .unwrap()
                    .received_bytes,
                30
            );
            manager.shutdown().await;
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn stop_rechecks_finalization_after_waiting_for_writer_ownership() {
        for state in [TaskState::Finalizing, TaskState::Pausing] {
            for intent in [StopIntent::Pause, StopIntent::Cancel] {
                let root = tempfile::tempdir().unwrap();
                let record = stored(root.path(), "3", TaskState::Running);
                let manager = DownloadManager::build(
                    DownloadConfig::default(),
                    Ok(None),
                    DownloadDocument {
                        version: 1,
                        revision: 1,
                        tasks: vec![record.clone()],
                    },
                )
                .unwrap();
                let writer = manager.inner.records.writes.lock().unwrap();
                let owner = manager.inner.clone();
                let id = record.task.id.clone();
                let attempt = record.task.attempt_id.clone();
                let (started_tx, started_rx) = std::sync::mpsc::channel();
                let stopping = std::thread::spawn(move || {
                    started_tx.send(()).unwrap();
                    owner.records.request_stop(&id, &attempt, intent)
                });
                started_rx.recv().unwrap();
                manager.inner.records.state.lock().unwrap().entries[0]
                    .stored
                    .task
                    .state = state;
                drop(writer);
                assert!(!stopping.join().unwrap());
                assert_eq!(manager.list()[0].state, state);
                assert!(
                    !manager.inner.records.state.lock().unwrap().entries[0]
                        .control
                        .cancel
                        .is_cancelled()
                );
                manager.shutdown().await;
            }
        }
    }

    #[tokio::test]
    async fn interrupted_tasks_fill_capacity_and_completed_records_free_it() {
        let root = tempfile::tempdir().unwrap();
        let records = (0..102)
            .map(|id| stored(root.path(), &id.to_string(), TaskState::Interrupted))
            .collect();
        let manager = DownloadManager::build(
            DownloadConfig::default(),
            Ok(None),
            DownloadDocument {
                version: 1,
                revision: 1,
                tasks: records,
            },
        )
        .unwrap();
        let _slots = manager
            .inner
            .slots
            .clone()
            .acquire_many_owned(2)
            .await
            .unwrap();
        let rejected = manager
            .start(vec![source("103")], root.path())
            .await
            .unwrap();
        assert!(rejected.task_ids.is_empty());
        assert_eq!(rejected.failures.len(), 1);
        {
            let mut state = manager.inner.records.state.lock().unwrap();
            state.entries[0].stored.task.state = TaskState::Completed;
        }
        let admitted = manager
            .start(vec![source("103")], root.path())
            .await
            .unwrap();
        assert_eq!(admitted.task_ids.len(), 1);
        assert!(admitted.failures.is_empty());
        assert_eq!(manager.list().len(), 103);
        manager.shutdown().await;
    }

    #[tokio::test]
    async fn restarting_cancelled_task_rechecks_dedup_using_actual_quality() {
        let root = tempfile::tempdir().unwrap();
        let mut cancelled = stored(root.path(), "3", TaskState::Cancelled);
        cancelled.task.quality = crate::media::Quality::Smooth;
        let existing = stored(root.path(), "3", TaskState::Paused);
        let manager = DownloadManager::build(
            DownloadConfig::default(),
            Ok(None),
            DownloadDocument {
                version: 1,
                revision: 1,
                tasks: vec![cancelled.clone(), existing],
            },
        )
        .unwrap();
        let gate = crate::lifecycle::ExitController::default();
        let result = manager
            .act(
                DownloadActionRequest {
                    task_id: cancelled.task.id.clone(),
                    attempt_id: cancelled.task.attempt_id.clone(),
                    action: DownloadAction::Restart,
                },
                Some(source("3")),
                Arc::new(gate.enter().await.unwrap()),
            )
            .await
            .unwrap();

        assert!(matches!(result, DownloadActionResult::Skipped { .. }));
        assert_eq!(
            manager.task(&cancelled.task.id).unwrap().attempt_id,
            cancelled.task.attempt_id
        );
        assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 0);
        manager.shutdown().await;
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn filesystem_reservation_wait_does_not_block_task_observation_or_cancellation() {
        let root = tempfile::tempdir().unwrap();
        let manager = Arc::new(DownloadManager::new(DownloadConfig::default()).unwrap());
        manager.start(Vec::new(), root.path()).await.unwrap();
        let _slots = manager.inner.slots.acquire_many(2).await.unwrap();
        let directory = manager
            .inner
            .directories
            .lock()
            .unwrap()
            .values()
            .next()
            .unwrap()
            .clone();
        let (admission, observing, responsive, reservation_started) = {
            let reservation_lock = super::super::files::hold_reservations(&directory);
            let owner = manager.clone();
            let target = root.path().to_owned();
            let admission = tokio::spawn(async move {
                owner
                    .start(
                        vec![PreparedDownload {
                            metadata: serde_json::from_value(serde_json::json!({
                                "content": {
                                    "programmeId": "1",
                                    "dateId": "2",
                                    "contentId": "3"
                                },
                                "programmeName": "News",
                                "broadcastDate": "2026-10-17",
                                "title": "Clip",
                                "cover": null
                            }))
                            .unwrap(),
                            content: super::super::ContentRef {
                                programme_id: "1".into(),
                                date_id: "2".into(),
                                content_id: "3".into(),
                            },
                            filename: "clip.mp4".into(),
                            quality: crate::media::Quality::Standard,
                            url: "https://fscgc.scgchc.com/clip.mp4".into(),
                        }],
                        &target,
                    )
                    .await
            });
            let deadline = std::time::Instant::now() + Duration::from_secs(1);
            while manager.inner.send.capacity()
                == manager.inner.config.queue_capacity + TRANSFER_CONCURRENCY
                && std::time::Instant::now() < deadline
            {
                std::thread::yield_now();
            }
            let reservation_started = manager.inner.send.capacity()
                < manager.inner.config.queue_capacity + TRANSFER_CONCURRENCY;
            let observer = manager.clone();
            let (observed, observation) = std::sync::mpsc::channel();
            let observing = std::thread::spawn(move || {
                observer.cancel("unknown");
                observed.send(observer.list()).unwrap();
            });

            let responsive = observation.recv_timeout(Duration::from_millis(250));

            drop(reservation_lock);
            (admission, observing, responsive, reservation_started)
        };
        let admitted = admission.await.unwrap();
        observing.join().unwrap();
        manager.shutdown().await;

        assert!(admitted.is_ok());
        assert!(
            reservation_started,
            "admission never reached directory reservation"
        );
        assert!(
            responsive.is_ok(),
            "filesystem reservation held the task-state lock"
        );
    }
}
