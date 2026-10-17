use super::{
    files::{DownloadDirectory, Reservation},
    store::{DownloadDocument, DownloadStore, StoredTask},
    worker::{self, storage},
    *,
};
use crate::{
    error::{AppError, ErrorCode, Result},
    lifecycle::OperationGuard,
    media::policy,
};
use futures_util::FutureExt;
use reqwest::{Client, Url};
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::{
    sync::{Semaphore, mpsc, watch},
    task::JoinHandle,
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use uuid::Uuid;

const TRANSFER_CONCURRENCY: usize = 2;

pub struct DownloadConfig {
    pub upstream_origins: Vec<String>,
    pub header_timeout: Duration,
    pub idle_timeout: Duration,
    pub queue_capacity: usize,
}
impl Default for DownloadConfig {
    fn default() -> Self {
        Self {
            upstream_origins: policy::default_origins(),
            header_timeout: Duration::from_secs(20),
            idle_timeout: Duration::from_secs(30),
            queue_capacity: 100,
        }
    }
}

pub(super) struct Control {
    pub cancel: CancellationToken,
    pub intent: Mutex<StopIntent>,
    pub settled: watch::Sender<bool>,
    pub checkpoint_failed: std::sync::atomic::AtomicBool,
}
impl Control {
    pub(super) fn new(settled: bool) -> Arc<Self> {
        Arc::new(Self {
            cancel: CancellationToken::new(),
            intent: Mutex::new(StopIntent::Cancel),
            settled: watch::channel(settled).0,
            checkpoint_failed: std::sync::atomic::AtomicBool::new(false),
        })
    }
    pub fn stop(&self, intent: StopIntent) {
        *self.intent.lock().unwrap() = intent;
        self.cancel.cancel();
    }
    pub async fn wait(&self) {
        let mut settled = self.settled.subscribe();
        while !*settled.borrow_and_update() {
            if settled.changed().await.is_err() {
                break;
            }
        }
    }
}

pub(super) struct Entry {
    pub stored: StoredTask,
    pub control: Arc<Control>,
}
pub(super) struct State {
    pub accepting: bool,
    pub entries: Vec<Entry>,
    pub revision: u64,
}
type Listener = Arc<dyn Fn(DownloadTask) -> bool + Send + Sync>;
type EventListener = Arc<dyn Fn(DownloadEvent) -> bool + Send + Sync>;

pub(super) struct Inner {
    pub state: Mutex<State>,
    pub admission: Arc<tokio::sync::Mutex<()>>,
    pub writes: Mutex<()>,
    #[cfg(test)]
    before_save: Mutex<Option<Box<dyn FnOnce() + Send>>>,
    pub store: Result<Option<DownloadStore>>,
    pub epoch: String,
    listeners: Mutex<HashMap<String, Listener>>,
    event_listeners: Mutex<HashMap<String, EventListener>>,
    pub directories: Mutex<HashMap<PathBuf, Arc<DownloadDirectory>>>,
    pub send: mpsc::Sender<Job>,
    pub slots: Arc<Semaphore>,
    stop: CancellationToken,
    tracker: TaskTracker,
    pub config: DownloadConfig,
    pub origins: Vec<Url>,
    pub client: Client,
}

pub(super) struct Job {
    pub id: String,
    pub attempt: String,
    pub url: String,
    pub reservation: Reservation,
    pub control: Arc<Control>,
    pub checkpoint: journal::ResumeCheckpoint,
    pub resume: bool,
}

pub struct DownloadManager {
    pub(super) inner: Arc<Inner>,
    dispatcher: tokio::sync::Mutex<Option<JoinHandle<()>>>,
}

impl DownloadManager {
    pub async fn prepare(
        &self,
        service: &crate::programmes::ProgrammeService,
        request: DownloadRequest,
    ) -> Result<PreparedBatch> {
        self.inner.available()?;
        tokio::select! { biased; _ = self.inner.stop.cancelled() => Err(closing()), result = super::prepare::prepare_downloads(service, request, &self.inner.origins) => result }
    }

    /// Creates an ephemeral owner for embedding/tests. Desktop composition uses open.
    pub fn new(config: DownloadConfig) -> Result<Self> {
        Self::build(
            config,
            Ok(None),
            DownloadDocument {
                version: 1,
                ..Default::default()
            },
        )
    }

    /// A corrupt/locked index disables downloads without disabling the rest of the application.
    pub async fn open(config: DownloadConfig, path: PathBuf) -> Result<Self> {
        let loaded = tokio::task::spawn_blocking(move || {
            let store = DownloadStore::open(path.clone())?;
            let document = DownloadStore::load(&path)?;
            Ok((store, document))
        })
        .await
        .map_err(|error| {
            AppError::with_source(ErrorCode::Storage, "下载记录读取异常终止", error)
        })?;
        match loaded {
            Ok((store, document)) => {
                let manager = Self::build(config, Ok(Some(store)), document)?;
                manager.recover().await;
                Ok(manager)
            }
            Err(error) => Self::unavailable(config, error),
        }
    }

    pub fn unavailable(config: DownloadConfig, error: AppError) -> Result<Self> {
        Self::build(
            config,
            Err(error.reported("open download index")),
            DownloadDocument {
                version: 1,
                ..Default::default()
            },
        )
    }

    fn build(
        config: DownloadConfig,
        store: Result<Option<DownloadStore>>,
        document: DownloadDocument,
    ) -> Result<Self> {
        if config.queue_capacity == 0 || config.queue_capacity > 100 {
            return Err(AppError::new(ErrorCode::InvalidInput, "下载队列容量无效"));
        }
        let origins = policy::parse_origins(&config.upstream_origins)?;
        let client = Client::builder()
            .user_agent(crate::media::USER_AGENT)
            .redirect(reqwest::redirect::Policy::none())
            .gzip(false)
            .read_timeout(config.idle_timeout)
            .build()
            .map_err(|error| {
                AppError::with_source(
                    ErrorCode::Upstream,
                    "无法初始化下载服务",
                    error.without_url(),
                )
            })?;
        let (send, mut receive) =
            mpsc::channel::<Job>(config.queue_capacity + TRANSFER_CONCURRENCY);
        let inner = Arc::new(Inner {
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
            admission: Arc::default(),
            writes: Mutex::new(()),
            #[cfg(test)]
            before_save: Mutex::new(None),
            store,
            epoch: Uuid::new_v4().to_string(),
            listeners: Mutex::default(),
            event_listeners: Mutex::default(),
            directories: Mutex::default(),
            send,
            slots: Arc::new(Semaphore::new(TRANSFER_CONCURRENCY)),
            stop: CancellationToken::new(),
            tracker: TaskTracker::new(),
            config,
            origins,
            client,
        });
        let owner = inner.clone();
        let dispatcher = tokio::spawn(async move {
            loop {
                let job = tokio::select! { biased; _ = owner.stop.cancelled() => { receive.close(); receive.recv().await }, job = receive.recv() => job };
                let Some(job) = job else {
                    break;
                };
                let task_owner = owner.clone();
                let id = job.id.clone();
                let attempt = job.attempt.clone();
                let control = job.control.clone();
                owner.tracker.spawn(async move {
                    if std::panic::AssertUnwindSafe(worker::run(task_owner.clone(), job))
                        .catch_unwind()
                        .await
                        .is_err()
                    {
                        let _ = task_owner
                            .change(id, attempt, |record| {
                                record.task.state = TaskState::Failed;
                                record.task.error = Some("下载任务异常终止，请检查临时文件".into());
                            })
                            .await;
                    }
                    control.settled.send_replace(true);
                });
            }
        });
        Ok(Self {
            inner,
            dispatcher: tokio::sync::Mutex::new(Some(dispatcher)),
        })
    }

    pub async fn start(
        &self,
        files: Vec<PreparedDownload>,
        directory: &Path,
    ) -> Result<DownloadStart> {
        self.start_owned(files, directory, None).await
    }

    /// Admission and lifecycle guards stay in the blocking worker through durable acceptance.
    pub async fn start_owned(
        &self,
        files: Vec<PreparedDownload>,
        directory: &Path,
        operation: Option<Arc<OperationGuard>>,
    ) -> Result<DownloadStart> {
        let admission = self.inner.admission.clone().lock_owned().await;
        let owner = self.inner.clone();
        let path = directory.to_owned();
        tokio::task::spawn_blocking(move || {
            let _guards = (admission, operation);
            owner.available()?;
            if !owner.state.lock().unwrap().accepting || owner.stop.is_cancelled() {
                return Err(closing());
            }
            let directory = owner.directory(&path)?;
            let mut result = DownloadStart::default();
            for file in files {
                let content_id = file.content.content_id.clone();
                match owner.admit(file, &directory) {
                    Ok(id) => result.task_ids.push(id),
                    Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
                    Err(error) => result.failures.push(FileFailure {
                        content_id,
                        message: error.reported("admit download").message,
                    }),
                }
            }
            Ok(result)
        })
        .await
        .map_err(|error| AppError::with_source(ErrorCode::Storage, "下载准备异常终止", error))?
    }

    pub fn list(&self) -> Vec<DownloadTask> {
        self.inner
            .state
            .lock()
            .unwrap()
            .entries
            .iter()
            .map(|entry| entry.stored.task.clone())
            .collect()
    }
    pub fn snapshot(&self) -> Result<DownloadSnapshot> {
        self.inner.available()?;
        let state = self.inner.state.lock().unwrap();
        Ok(DownloadSnapshot {
            epoch: self.inner.epoch.clone(),
            revision: state.revision,
            tasks: state
                .entries
                .iter()
                .map(|entry| entry.stored.task.clone())
                .collect(),
        })
    }
    pub fn has_active(&self) -> bool {
        self.inner
            .state
            .lock()
            .unwrap()
            .entries
            .iter()
            .any(|entry| entry.stored.task.active())
    }
    pub fn cancel(&self, id: &str) {
        if let Some(entry) = self
            .inner
            .state
            .lock()
            .unwrap()
            .entries
            .iter()
            .find(|entry| entry.stored.task.id == id && entry.stored.task.active())
        {
            entry.control.stop(StopIntent::Cancel);
        }
    }
    pub fn subscribe(
        &self,
        listener: impl Fn(DownloadTask) -> bool + Send + Sync + 'static,
    ) -> String {
        let id = Uuid::new_v4().to_string();
        self.inner
            .listeners
            .lock()
            .unwrap()
            .insert(id.clone(), Arc::new(listener));
        id
    }
    pub fn unsubscribe(&self, id: &str) {
        self.inner.listeners.lock().unwrap().remove(id);
    }
    pub fn subscribe_events(
        &self,
        listener: impl Fn(DownloadEvent) -> bool + Send + Sync + 'static,
    ) -> Result<String> {
        self.inner.available()?;
        let id = Uuid::new_v4().to_string();
        self.inner
            .event_listeners
            .lock()
            .unwrap()
            .insert(id.clone(), Arc::new(listener));
        Ok(id)
    }
    pub fn unsubscribe_events(&self, id: &str) {
        self.inner.event_listeners.lock().unwrap().remove(id);
    }

    /// Stops I/O and commits checkpoints. Failure leaves admission recoverable for a rejected quit.
    pub async fn prepare_shutdown(&self) -> Result<()> {
        if !matches!(&self.inner.store, Ok(Some(_))) {
            return Ok(());
        }
        self.inner.state.lock().unwrap().accepting = false;
        let admission = self.inner.admission.lock().await;
        let active: Vec<_> = self
            .inner
            .state
            .lock()
            .unwrap()
            .entries
            .iter()
            .filter(|entry| entry.stored.task.active())
            .map(|entry| (entry.stored.task.id.clone(), entry.control.clone()))
            .collect();
        for (_, control) in &active {
            control.stop(StopIntent::Exit);
        }
        for (_, control) in &active {
            control.wait().await;
        }
        drop(admission);
        let failure = self
            .inner
            .state
            .lock()
            .unwrap()
            .entries
            .iter()
            .any(|entry| {
                entry
                    .control
                    .checkpoint_failed
                    .load(std::sync::atomic::Ordering::SeqCst)
            });
        if failure {
            self.inner.state.lock().unwrap().accepting = true;
            return Err(AppError::new(
                ErrorCode::Storage,
                "部分下载进度未能安全保存，请重试或明确选择强制退出",
            ));
        }
        Ok(())
    }

    pub fn reopen_admission(&self) {
        if !self.inner.stop.is_cancelled() {
            self.inner.state.lock().unwrap().accepting = true;
        }
    }

    /// Final shutdown awaits every writer; durable owners preserve artifacts even on failure.
    pub async fn shutdown(&self) {
        self.inner.state.lock().unwrap().accepting = false;
        let durable = matches!(&self.inner.store, Ok(Some(_)));
        for entry in &self.inner.state.lock().unwrap().entries {
            if entry.stored.task.active() {
                entry.control.stop(if durable {
                    StopIntent::Exit
                } else {
                    StopIntent::Cancel
                });
            }
        }
        self.inner.stop.cancel();
        let _admission = self.inner.admission.lock().await;
        let mut dispatcher = self.dispatcher.lock().await;
        if let Some(task) = dispatcher.take()
            && let Err(error) = task.await
        {
            AppError::with_source(ErrorCode::Storage, "下载调度异常终止", error)
                .reported("shutdown downloads");
        }
        self.inner.tracker.close();
        self.inner.tracker.wait().await;
        self.inner.directories.lock().unwrap().clear();
    }

    async fn recover(&self) {
        let owner = self.inner.clone();
        if let Err(error) = tokio::task::spawn_blocking(move || owner.recover_blocking()).await {
            AppError::with_source(ErrorCode::Storage, "下载恢复异常终止", error)
                .reported("recover downloads");
        }
    }
}

impl Drop for DownloadManager {
    fn drop(&mut self) {
        self.inner.state.lock().unwrap().accepting = false;
        for entry in &self.inner.state.lock().unwrap().entries {
            if entry.stored.task.active() {
                entry.control.stop(StopIntent::Exit);
            }
        }
        self.inner.stop.cancel();
    }
}

impl Inner {
    pub fn available(&self) -> Result<()> {
        self.store.as_ref().map(|_| ()).map_err(Clone::clone)
    }
    pub fn directory(&self, path: &Path) -> Result<Arc<DownloadDirectory>> {
        let root = path.canonicalize().map_err(storage)?;
        if let Some(directory) = self.directories.lock().unwrap().get(&root).cloned() {
            return Ok(directory);
        }
        let directory = DownloadDirectory::open(&root).map_err(storage)?;
        self.directories
            .lock()
            .unwrap()
            .insert(root, directory.clone());
        Ok(directory)
    }

    pub(super) fn emit_event(&self, event: DownloadEvent) {
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
    pub(super) fn emit(&self, task: DownloadTask, revision: u64) {
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

    pub(super) fn save(&self, tasks: Vec<StoredTask>, revision: u64) -> Result<()> {
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
        let (mut records, revision) = {
            let state = self.state.lock().unwrap();
            (
                state
                    .entries
                    .iter()
                    .map(|entry| entry.stored.clone())
                    .collect::<Vec<_>>(),
                state.revision + 1,
            )
        };
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

    fn admit(&self, file: PreparedDownload, directory: &Arc<DownloadDirectory>) -> Result<String> {
        policy::target(&file.url, &self.origins)?;
        file.metadata.validate()?;
        let _writer = self.writes.lock().unwrap();
        {
            let state = self.state.lock().unwrap();
            if !state.accepting || self.stop.is_cancelled() {
                return Err(closing());
            }
            if let Some(entry) = state.entries.iter().find(|entry| {
                entry.stored.task.unfinished()
                    && entry.stored.task.content == file.content
                    && entry.stored.task.quality == file.quality
                    && entry.stored.directory == directory.path()
            }) {
                return Ok(entry.stored.task.id.clone());
            }
            if state
                .entries
                .iter()
                .filter(|entry| entry.stored.task.unfinished())
                .count()
                >= self.config.queue_capacity + TRANSFER_CONCURRENCY
            {
                return Err(AppError::new(
                    ErrorCode::InvalidInput,
                    "下载队列已满，请稍后重试",
                ));
            }
        }
        let permit = self
            .send
            .try_reserve()
            .map_err(|_| AppError::new(ErrorCode::InvalidInput, "下载队列已满，请稍后重试"))?;
        let (writer, mut reservation) = directory.reserve(&file.filename).map_err(storage)?;
        drop(writer);
        let id = Uuid::new_v4().to_string();
        let attempt = Uuid::new_v4().to_string();
        let record = match reservation.upgrade(id.clone(), attempt.clone()) {
            Ok(record) => record,
            Err(error) => {
                reservation.cleanup().map_err(storage)?;
                return Err(storage(error));
            }
        };
        let task = DownloadTask {
            id: id.clone(),
            attempt_id: attempt.clone(),
            content: file.content,
            metadata: file.metadata,
            filename: reservation.filename().into(),
            quality: file.quality,
            state: TaskState::Queued,
            received_bytes: 0,
            total_bytes: None,
            error: None,
            revision: 1,
            created_at: chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
            can_resume: false,
            file_available: false,
            has_partial: true,
        };
        let stored = StoredTask {
            task: task.clone(),
            directory: directory.path().into(),
            reservation: Some(record.clone()),
            completed_identity: None,
        };
        let (mut records, revision) = {
            let state = self.state.lock().unwrap();
            (
                state
                    .entries
                    .iter()
                    .map(|entry| entry.stored.clone())
                    .collect::<Vec<_>>(),
                state.revision + 1,
            )
        };
        records.push(stored.clone());
        if let Err(error) = self.save(records, revision) {
            if store::replacement_committed(&error) {
                let mut stored = stored;
                stored.task.state = TaskState::Failed;
                stored.task.error = Some(error.message.clone());
                let task = stored.task.clone();
                let revision = {
                    let mut state = self.state.lock().unwrap();
                    let control = Control::new(true);
                    control
                        .checkpoint_failed
                        .store(true, std::sync::atomic::Ordering::SeqCst);
                    state.entries.push(Entry { stored, control });
                    state.revision += 1;
                    state.revision
                };
                reservation.retain();
                self.emit(task, revision);
            } else {
                reservation.cleanup().map_err(storage)?;
            }
            return Err(error);
        }
        let control = Control::new(false);
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
        permit.send(Job {
            id: id.clone(),
            attempt,
            url: file.url,
            reservation,
            control,
            checkpoint: record.checkpoint,
            resume: false,
        });
        Ok(id)
    }

    fn recover_blocking(&self) {
        let records: Vec<_> = self
            .state
            .lock()
            .unwrap()
            .entries
            .iter()
            .map(|entry| entry.stored.clone())
            .collect();
        for mut record in records {
            let recovered = (|| -> Result<()> {
                if record.task.state == TaskState::Completed || record.completed_identity.is_some()
                {
                    let identity = record
                        .completed_identity
                        .as_ref()
                        .ok_or_else(|| AppError::new(ErrorCode::Storage, "下载文件身份缺失"))?;
                    identity
                        .open_verified(&record.directory.join(&record.task.filename), false)
                        .map_err(storage)?;
                    record.task.state = TaskState::Completed;
                    record.task.file_available = true;
                    record.task.has_partial = false;
                    record.task.can_resume = false;
                    record.task.error = None;
                    return Ok(());
                }
                if !record.task.unfinished() {
                    return Ok(());
                }
                let directory = self.directory(&record.directory)?;
                if let Some(reservation) = &record.reservation {
                    if reservation.phase != journal::PublicationPhase::Writing
                        && let Ok(file) = reservation
                            .checkpoint
                            .file_identity
                            .open_verified(&record.directory.join(&reservation.filename), false)
                        && file.metadata().map_err(storage)?.len()
                            == reservation.checkpoint.committed_bytes
                    {
                        record.task.filename = reservation.filename.clone();
                        record.task.state = TaskState::Completed;
                        record.task.received_bytes = reservation.checkpoint.committed_bytes;
                        record.task.file_available = true;
                        record.task.has_partial = false;
                        record.task.can_resume = false;
                        record.completed_identity =
                            Some(reservation.checkpoint.file_identity.clone());
                        return Ok(());
                    }
                    directory
                        .recover_reservation(reservation)
                        .map_err(storage)?
                        .retain();
                    record.task.received_bytes = reservation.checkpoint.committed_bytes;
                    record.task.total_bytes = reservation.checkpoint.total_bytes;
                    record.task.can_resume = reservation.checkpoint.resumable();
                    record.task.has_partial = true;
                }
                record.task.state = TaskState::Interrupted;
                Ok(())
            })();
            if let Err(error) = recovered {
                record.task.state = if record.completed_identity.is_some() {
                    TaskState::Missing
                } else {
                    TaskState::Failed
                };
                record.task.file_available = false;
                record.task.can_resume = false;
                record.task.error = Some(error.reported("recover download").message);
            }
            let id = record.task.id.clone();
            let attempt = record.task.attempt_id.clone();
            let publication = (record.task.state == TaskState::Completed)
                .then(|| record.reservation.clone())
                .flatten();
            let directory = record.directory.clone();
            match self.change_blocking(&id, &attempt, |entry| *entry = record) {
                Ok(_) => {
                    if let Some(publication) = publication
                        && let Err(error) = self.directory(&directory).and_then(|directory| {
                            directory.complete_recovered(&publication).map_err(storage)
                        })
                    {
                        self.report_failure(&id, &attempt, error);
                    }
                }
                Err(error) => self.report_failure(&id, &attempt, error),
            }
        }
    }
}

fn closing() -> AppError {
    AppError::new(ErrorCode::Cancelled, "应用正在退出，无法操作下载")
}

#[cfg(test)]
mod tests {
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
            *manager.inner.before_save.lock().unwrap() = Some(Box::new(move || {
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
                manager.inner.progress(
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
                let writer = manager.inner.writes.lock().unwrap();
                let owner = manager.inner.clone();
                let id = record.task.id.clone();
                let attempt = record.task.attempt_id.clone();
                let (started_tx, started_rx) = std::sync::mpsc::channel();
                let stopping = std::thread::spawn(move || {
                    started_tx.send(()).unwrap();
                    owner.request_stop(&id, &attempt, intent)
                });
                started_rx.recv().unwrap();
                manager.inner.state.lock().unwrap().entries[0]
                    .stored
                    .task
                    .state = state;
                drop(writer);
                assert!(!stopping.join().unwrap());
                assert_eq!(manager.list()[0].state, state);
                assert!(
                    !manager.inner.state.lock().unwrap().entries[0]
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
            let mut state = manager.inner.state.lock().unwrap();
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
                            metadata: serde_json::from_value(serde_json::json!({"content":{"programmeId":"1","dateId":"2","contentId":"3"},"programmeName":"News","broadcastDate":"2026-10-17","title":"Clip","cover":null})).unwrap(),
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
