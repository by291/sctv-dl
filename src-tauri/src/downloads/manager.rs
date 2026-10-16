use super::{
    DownloadStart, DownloadTask, FileFailure, PreparedDownload, TaskState,
    files::{DownloadDirectory, Reservation},
    worker::{self, storage},
};
use crate::{
    error::{AppError, ErrorCode, Result},
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
    sync::{Semaphore, mpsc},
    task::JoinHandle,
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use uuid::Uuid;

const TRANSFER_CONCURRENCY: usize = 2;

pub struct DownloadConfig {
    pub upstream_origin: String,
    pub header_timeout: Duration,
    pub idle_timeout: Duration,
    pub queue_capacity: usize,
}

impl Default for DownloadConfig {
    fn default() -> Self {
        Self {
            upstream_origin: "https://fscgc.scgchc.com/".into(),
            header_timeout: Duration::from_secs(20),
            idle_timeout: Duration::from_secs(30),
            queue_capacity: 100,
        }
    }
}

struct Entry {
    task: DownloadTask,
    directory: PathBuf,
    cancel: CancellationToken,
}

struct State {
    accepting: bool,
    entries: Vec<Entry>,
}

type Listener = Arc<dyn Fn(DownloadTask) -> bool + Send + Sync>;
pub(super) struct Inner {
    state: Mutex<State>,
    admission: Arc<tokio::sync::Mutex<()>>,
    listeners: Mutex<HashMap<String, Listener>>,
    directories: Mutex<HashMap<PathBuf, Arc<DownloadDirectory>>>,
    send: mpsc::Sender<Job>,
    pub(super) slots: Arc<Semaphore>,
    stop: CancellationToken,
    tracker: TaskTracker,
    pub(super) config: DownloadConfig,
    origin: Url,
    pub(super) client: Client,
}

pub(super) struct Job {
    pub(super) id: String,
    pub(super) url: String,
    pub(super) reservation: Reservation,
    pub(super) cancel: CancellationToken,
}

pub struct DownloadManager {
    pub(super) inner: Arc<Inner>,
    dispatcher: tokio::sync::Mutex<Option<JoinHandle<()>>>,
}

impl DownloadManager {
    pub async fn prepare(
        &self,
        service: &crate::programmes::ProgrammeService,
        request: super::DownloadRequest,
    ) -> Result<super::PreparedBatch> {
        tokio::select! {
            biased;
            _ = self.inner.stop.cancelled() => Err(AppError::new(ErrorCode::Cancelled, "应用正在退出")),
            result = super::prepare::prepare_downloads(service, request, &self.inner.origin) => result,
        }
    }

    pub fn new(config: DownloadConfig) -> Result<Self> {
        if config.queue_capacity == 0 || config.queue_capacity > 10_000 {
            return Err(AppError::new(ErrorCode::InvalidInput, "下载队列容量无效"));
        }
        let origin = Url::parse(&config.upstream_origin).map_err(|error| {
            AppError::with_source(ErrorCode::InvalidInput, "视频服务地址无效", error)
        })?;
        let client = Client::builder()
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
        let (send, mut receive) = mpsc::channel::<Job>(config.queue_capacity);
        let inner = Arc::new(Inner {
            state: Mutex::new(State {
                accepting: true,
                entries: Vec::new(),
            }),
            admission: Arc::default(),
            listeners: Mutex::default(),
            directories: Mutex::default(),
            send,
            slots: Arc::new(Semaphore::new(TRANSFER_CONCURRENCY)),
            stop: CancellationToken::new(),
            tracker: TaskTracker::new(),
            config,
            origin,
            client,
        });
        let owner = inner.clone();
        let dispatcher = tokio::spawn(async move {
            // Accepted jobs are bounded separately, including futures waiting for a slot.
            loop {
                let job = tokio::select! {
                    biased;
                    _ = owner.stop.cancelled() => { receive.close(); receive.recv().await },
                    job = receive.recv() => job,
                };
                let Some(job) = job else {
                    break;
                };
                let task_owner = owner.clone();
                let id = job.id.clone();
                owner.tracker.spawn(async move {
                    if std::panic::AssertUnwindSafe(worker::run(task_owner.clone(), job))
                        .catch_unwind()
                        .await
                        .is_err()
                    {
                        task_owner.update(&id, |task| {
                            task.state = TaskState::Failed;
                            task.error = Some("下载任务异常终止，请重试并检查临时文件".into());
                        });
                    }
                });
            }
        });
        Ok(Self {
            inner,
            dispatcher: tokio::sync::Mutex::new(Some(dispatcher)),
        })
    }

    /// Reserves and queues each accepted file; transfer completion is reported through task state.
    /// Blocking preparation retains its admission guard even if the caller drops this future.
    pub async fn start(
        &self,
        files: Vec<PreparedDownload>,
        directory: &Path,
    ) -> Result<DownloadStart> {
        let admission = self.inner.admission.clone().lock_owned().await;
        let owner = self.inner.clone();
        let directory = directory.to_owned();
        tokio::task::spawn_blocking(move || {
            // The blocking operation owns the guard even if its caller drops the future.
            let _admission = admission;
            if !owner.state.lock().unwrap().accepting || owner.stop.is_cancelled() {
                return Err(AppError::new(ErrorCode::Cancelled, "应用正在退出"));
            }
            let root = directory.canonicalize().map_err(storage)?;
            let directory = {
                let mut directories = owner.directories.lock().unwrap();
                if let Some(directory) = directories.get(&root) {
                    directory.clone()
                } else {
                    let directory = DownloadDirectory::open(&root).map_err(storage)?;
                    directories.insert(root.clone(), directory.clone());
                    directory
                }
            };
            let mut result = DownloadStart::default();
            for file in files {
                let content_id = file.content.content_id.clone();
                match owner.admit(file, &directory) {
                    Ok(id) => result.task_ids.push(id),
                    Err(error) if error.code == ErrorCode::Cancelled => return Err(error),
                    Err(error) => {
                        let error = error.reported("prepare download file");
                        result.failures.push(FileFailure {
                            content_id,
                            message: error.message,
                        });
                    }
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
            .map(|entry| entry.task.clone())
            .collect()
    }

    pub fn has_active(&self) -> bool {
        let state = self.inner.state.lock().unwrap();
        state
            .entries
            .iter()
            .any(|entry| !entry.task.state.is_terminal())
    }

    pub fn cancel(&self, id: &str) {
        if let Some(entry) = self
            .inner
            .state
            .lock()
            .unwrap()
            .entries
            .iter()
            .find(|entry| entry.task.id == id && !entry.task.state.is_terminal())
        {
            entry.cancel.cancel();
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
    /// Cancels and awaits preparation and transfers before releasing the directory locks.
    pub async fn shutdown(&self) {
        self.inner.state.lock().unwrap().accepting = false;
        self.inner.stop.cancel();
        let _admission = self.inner.admission.lock().await;
        // Hold the guard through waiting so concurrent shutdown callers cannot return early.
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
}

impl Drop for DownloadManager {
    fn drop(&mut self) {
        self.inner.state.lock().unwrap().accepting = false;
        self.inner.stop.cancel();
    }
}

impl Inner {
    fn emit(&self, task: DownloadTask) {
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

    pub(super) fn update(&self, id: &str, update: impl FnOnce(&mut DownloadTask)) {
        self.update_task(id, true, update);
    }

    pub(super) fn record_progress(&self, id: &str, received: u64, publish: bool) {
        // Silent snapshots also advance revisions, so older emitted progress cannot replace them.
        self.update_task(id, publish, |task| task.received_bytes = received);
    }

    fn update_task(&self, id: &str, publish: bool, update: impl FnOnce(&mut DownloadTask)) {
        let task = {
            let mut state = self.state.lock().unwrap();
            let Some(entry) = state.entries.iter_mut().find(|entry| entry.task.id == id) else {
                return;
            };
            if entry.task.state.is_terminal() {
                return;
            }
            update(&mut entry.task);
            entry.task.revision += 1;
            publish.then(|| entry.task.clone())
        };
        if let Some(task) = task {
            self.emit(task);
        }
    }

    fn admit(&self, file: PreparedDownload, directory: &Arc<DownloadDirectory>) -> Result<String> {
        policy::target(&file.url, &self.origin)?;
        {
            let state = self.state.lock().unwrap();
            if !state.accepting || self.stop.is_cancelled() {
                return Err(AppError::new(
                    ErrorCode::Cancelled,
                    "应用正在退出，无法添加下载",
                ));
            }
            if let Some(entry) = state.entries.iter().find(|entry| {
                !entry.task.state.is_terminal()
                    && entry.task.content == file.content
                    && entry.task.quality == file.quality
                    && entry.directory == directory.path()
            }) {
                return Ok(entry.task.id.clone());
            }
            if state
                .entries
                .iter()
                .filter(|entry| !entry.task.state.is_terminal())
                .count()
                >= self.config.queue_capacity + TRANSFER_CONCURRENCY
            {
                return Err(AppError::new(
                    ErrorCode::InvalidInput,
                    "下载队列已满，请稍后重试",
                ));
            }
        }

        // Admission is serialized by the caller; keep slow reservation I/O outside task state.
        let permit = self
            .send
            .try_reserve()
            .map_err(|_| AppError::new(ErrorCode::InvalidInput, "下载队列已满，请稍后重试"))?;
        let (writer, reservation) = directory.reserve(&file.filename).map_err(storage)?;
        // Keep one identity handle per queued file; clone a writer only while executing.
        drop(writer);

        let mut state = self.state.lock().unwrap();
        if !state.accepting || self.stop.is_cancelled() {
            drop(state);
            reservation.cleanup().map_err(storage)?;
            return Err(AppError::new(
                ErrorCode::Cancelled,
                "应用正在退出，无法添加下载",
            ));
        }
        let id = Uuid::new_v4().to_string();
        let cancel = self.stop.child_token();
        let task = DownloadTask {
            id: id.clone(),
            content: file.content,
            filename: reservation.filename().into(),
            quality: file.quality,
            state: TaskState::Queued,
            received_bytes: 0,
            total_bytes: None,
            error: None,
            revision: 1,
        };
        state.entries.push(Entry {
            task: task.clone(),
            directory: directory.path().into(),
            cancel: cancel.clone(),
        });
        drop(state);
        self.emit(task);
        permit.send(Job {
            id: id.clone(),
            url: file.url,
            reservation,
            cancel,
        });
        Ok(id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
            while manager.inner.send.capacity() == manager.inner.config.queue_capacity
                && std::time::Instant::now() < deadline
            {
                std::thread::yield_now();
            }
            let reservation_started =
                manager.inner.send.capacity() < manager.inner.config.queue_capacity;
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
