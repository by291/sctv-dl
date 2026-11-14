use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::Duration,
};

use futures_util::FutureExt;
use reqwest::{Client, Url};
use tokio::{
    sync::{Semaphore, mpsc, watch},
    task::JoinHandle,
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use uuid::Uuid;

use super::{
    errors::{storage, with_rollback},
    files::{DownloadDirectory, Reservation},
    records::{Admission, TaskRecords},
    store::{DownloadDocument, DownloadStore, StoredTask},
    worker, *,
};
use crate::{
    error::{AppError, ErrorCode, Result},
    lifecycle::OperationGuard,
    media::policy,
};

pub(super) const TRANSFER_CONCURRENCY: usize = 2;
const MAX_QUEUE_CAPACITY: usize = 100;

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
            queue_capacity: MAX_QUEUE_CAPACITY,
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

pub(super) struct Inner {
    pub records: Arc<TaskRecords>,
    pub admission: Arc<tokio::sync::Mutex<()>>,
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
    pub mode: TransferMode,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum TransferMode {
    Full,
    Resume,
}

pub struct DownloadManager {
    pub(super) inner: Arc<Inner>,
    dispatcher: tokio::sync::Mutex<Option<JoinHandle<()>>>,
}

impl DownloadManager {
    /// Resolves programme sources while the owner is accepting work.
    pub async fn prepare(
        &self,
        service: &crate::programmes::ProgrammeService,
        request: DownloadRequest,
    ) -> Result<PreparedBatch> {
        self.inner.records.available()?;

        tokio::select! {
            biased;
            _ = self.inner.stop.cancelled() => Err(closing()),
            result = super::prepare::prepare_downloads(service, request, &self.inner.origins) => result,
        }
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

    /// Creates an owner that reports the saved index failure to callers.
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

    pub(super) fn build(
        config: DownloadConfig,
        store: Result<Option<DownloadStore>>,
        document: DownloadDocument,
    ) -> Result<Self> {
        if config.queue_capacity == 0 || config.queue_capacity > MAX_QUEUE_CAPACITY {
            return Err(AppError::new(ErrorCode::InvalidInput, "下载队列容量无效"));
        }

        let origins = policy::parse_origins(&config.upstream_origins)?;
        let client = Client::builder()
            .user_agent(crate::upstream::USER_AGENT)
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

        let (send, receive) = mpsc::channel::<Job>(config.queue_capacity + TRANSFER_CONCURRENCY);
        let inner = Arc::new(Inner {
            records: Arc::new(TaskRecords::new(store, document)),
            admission: Arc::default(),
            directories: Mutex::default(),
            send,
            slots: Arc::new(Semaphore::new(TRANSFER_CONCURRENCY)),
            stop: CancellationToken::new(),
            tracker: TaskTracker::new(),
            config,
            origins,
            client,
        });

        let dispatcher = tokio::spawn(dispatch_jobs(inner.clone(), receive));

        Ok(Self {
            inner,
            dispatcher: tokio::sync::Mutex::new(Some(dispatcher)),
        })
    }

    /// Starts a batch for an embedding caller without an application lifecycle guard.
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
            owner.records.available()?;
            if !owner.records.accepting() || owner.stop.is_cancelled() {
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

    /// Returns current download tasks for the legacy IPC adapter.
    pub fn list(&self) -> Vec<DownloadTask> {
        self.inner.records.list()
    }

    /// Returns tasks with their source epoch and snapshot revision.
    pub fn snapshot(&self) -> Result<DownloadSnapshot> {
        self.inner.records.snapshot()
    }

    /// Reports whether any queued or running work can delay exit.
    pub fn has_active(&self) -> bool {
        !self.inner.records.active_controls().is_empty()
    }

    /// Signals an active task to cancel without waiting for writer settlement.
    pub fn cancel(&self, id: &str) {
        if let Some((stored, control)) = self.inner.records.find(id, None)
            && stored.task.active()
        {
            control.stop(StopIntent::Cancel);
        }
    }

    /// Registers a listener for task updates from the legacy adapter.
    pub fn subscribe(
        &self,
        listener: impl Fn(DownloadTask) -> bool + Send + Sync + 'static,
    ) -> String {
        self.inner.records.subscribe(listener)
    }

    /// Removes a legacy task listener.
    pub fn unsubscribe(&self, id: &str) {
        self.inner.records.unsubscribe(id);
    }

    /// Registers a listener for revisioned task updates and removals.
    pub fn subscribe_events(
        &self,
        listener: impl Fn(DownloadEvent) -> bool + Send + Sync + 'static,
    ) -> Result<String> {
        self.inner.records.subscribe_events(listener)
    }

    /// Removes a revisioned event listener.
    pub fn unsubscribe_events(&self, id: &str) {
        self.inner.records.unsubscribe_events(id);
    }

    /// Stops I/O and commits checkpoints. Failure leaves admission recoverable for a rejected quit.
    pub async fn prepare_shutdown(&self) -> Result<()> {
        if !self.inner.records.durable() {
            return Ok(());
        }

        self.inner.records.set_accepting(false);
        let admission = self.inner.admission.lock().await;
        let active = self.inner.records.active_controls();
        for control in &active {
            control.stop(StopIntent::Exit);
        }

        for control in &active {
            control.wait().await;
        }

        drop(admission);

        let failure = self.inner.records.checkpoint_failed();
        if failure {
            self.inner.records.set_accepting(true);
            return Err(AppError::new(
                ErrorCode::Storage,
                "部分下载进度未能安全保存，请重试或明确选择强制退出",
            ));
        }
        Ok(())
    }

    /// Allows an exit attempt that was declined to accept work again.
    pub fn reopen_admission(&self) {
        if !self.inner.stop.is_cancelled() {
            self.inner.records.set_accepting(true);
        }
    }

    /// Final shutdown awaits every writer; durable owners preserve artifacts even on failure.
    pub async fn shutdown(&self) {
        self.inner.records.set_accepting(false);
        let durable = self.inner.records.durable();
        for control in self.inner.records.active_controls() {
            control.stop(if durable {
                StopIntent::Exit
            } else {
                StopIntent::Cancel
            });
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
        if let Err(error) =
            tokio::task::spawn_blocking(move || super::recovery::recover(&owner)).await
        {
            AppError::with_source(ErrorCode::Storage, "下载恢复异常终止", error)
                .reported("recover downloads");
        }
    }
}

impl Drop for DownloadManager {
    fn drop(&mut self) {
        self.inner.records.set_accepting(false);
        for control in self.inner.records.active_controls() {
            control.stop(StopIntent::Exit);
        }
        self.inner.stop.cancel();
    }
}

impl Inner {
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

    fn admit(&self, file: PreparedDownload, directory: &Arc<DownloadDirectory>) -> Result<String> {
        policy::target(&file.url, &self.origins)?;
        file.metadata.validate()?;
        match self
            .records
            .admission(&file, directory.path(), None, self.config.queue_capacity)?
        {
            Admission::Duplicate(id) => return Ok(id),
            Admission::Available => {}
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
                return Err(with_rollback(
                    storage(error),
                    reservation.cleanup().map_err(storage),
                ));
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

        let control = match self.records.insert(stored) {
            Ok(control) => control,
            Err(error) => {
                if store::replacement_committed(&error) {
                    reservation.retain();
                } else {
                    return Err(with_rollback(error, reservation.cleanup().map_err(storage)));
                }
                return Err(error);
            }
        };

        // Queue dispatch follows durable acceptance; a failed index commit never starts I/O.
        permit.send(Job {
            id: id.clone(),
            attempt,
            url: file.url,
            reservation,
            control,
            checkpoint: record.checkpoint,
            mode: TransferMode::Full,
        });
        Ok(id)
    }
}

async fn dispatch_jobs(owner: Arc<Inner>, mut receive: mpsc::Receiver<Job>) {
    loop {
        let job = tokio::select! {
            biased;
            _ = owner.stop.cancelled() => {
                // Stop new jobs and drain accepted jobs so their reservations still settle.
                receive.close();
                receive.recv().await
            }
            job = receive.recv() => job,
        };
        let Some(job) = job else {
            break;
        };

        owner.tracker.spawn(run_tracked_job(owner.clone(), job));
    }
}

async fn run_tracked_job(owner: Arc<Inner>, job: Job) {
    let task_id = job.id.clone();
    let attempt_id = job.attempt.clone();
    let control = job.control.clone();

    let outcome = std::panic::AssertUnwindSafe(worker::run(owner.clone(), job))
        .catch_unwind()
        .await;
    if outcome.is_err() {
        let failed = owner
            .records
            .change(task_id.clone(), attempt_id.clone(), |record| {
                record.task.state = TaskState::Failed;
                record.task.error = Some("下载任务异常终止，请检查临时文件".into());
            })
            .await;
        if let Err(error) = failed {
            owner.records.report_failure(&task_id, &attempt_id, error);
        }
    }

    // Waiters may proceed only after the writer and any panic-triggered settlement are done.
    control.settled.send_replace(true);
}

fn closing() -> AppError {
    AppError::new(ErrorCode::Cancelled, "应用正在退出，无法操作下载")
}
