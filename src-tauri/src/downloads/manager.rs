use super::{
    DownloadStart, DownloadTask, FileFailure, PreparedDownload, TaskState,
    files::{DownloadDirectory, Reservation},
};
use crate::{
    error::{AppError, Result},
    media::policy,
};
use futures_util::FutureExt;
use reqwest::{Client, Url};
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::{
    io::AsyncWriteExt,
    sync::{Semaphore, mpsc},
    task::JoinHandle,
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use uuid::Uuid;

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
struct Inner {
    state: Mutex<State>,
    admission: Arc<tokio::sync::Mutex<()>>,
    listeners: Mutex<HashMap<String, Listener>>,
    directories: Mutex<HashMap<PathBuf, Arc<DownloadDirectory>>>,
    send: mpsc::Sender<Job>,
    slots: Arc<Semaphore>,
    stop: CancellationToken,
    tracker: TaskTracker,
    config: DownloadConfig,
    origin: Url,
    client: Client,
}
struct Job {
    id: String,
    url: String,
    reservation: Reservation,
    cancel: CancellationToken,
}

pub struct DownloadManager {
    inner: Arc<Inner>,
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
            _ = self.inner.stop.cancelled() => Err(AppError::new("cancelled", "应用正在退出")),
            result = super::prepare::prepare_downloads(service, request, &self.inner.origin) => result,
        }
    }
    pub fn new(config: DownloadConfig) -> Result<Self> {
        if config.queue_capacity == 0 || config.queue_capacity > 10_000 {
            return Err(AppError::new("invalid-input", "下载队列容量无效"));
        }
        let origin = Url::parse(&config.upstream_origin)
            .map_err(|_| AppError::new("invalid-input", "视频服务地址无效"))?;
        let client = Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .gzip(false)
            .read_timeout(config.idle_timeout)
            .build()
            .map_err(|_| AppError::new("upstream", "无法初始化下载服务"))?;
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
            slots: Arc::new(Semaphore::new(2)),
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
                    if std::panic::AssertUnwindSafe(run(task_owner.clone(), job))
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
                return Err(AppError::new("cancelled", "应用正在退出"));
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
                    Err(error) if error.code == "cancelled" => return Err(error),
                    Err(error) => result.failures.push(FileFailure {
                        content_id,
                        message: error.message,
                    }),
                }
            }
            Ok(result)
        })
        .await
        .map_err(|_| AppError::new("storage", "下载准备异常终止"))?
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
        self.list().iter().any(|task| !task.state.is_terminal())
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
    pub async fn shutdown(&self) {
        self.inner.state.lock().unwrap().accepting = false;
        self.inner.stop.cancel();
        let _admission = self.inner.admission.lock().await;
        // Hold the guard through waiting so concurrent shutdown callers cannot return early.
        let mut dispatcher = self.dispatcher.lock().await;
        if let Some(task) = dispatcher.take() {
            let _ = task.await;
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
    fn update(&self, id: &str, update: impl FnOnce(&mut DownloadTask)) {
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
            entry.task.clone()
        };
        self.emit(task);
    }
    fn admit(&self, file: PreparedDownload, directory: &Arc<DownloadDirectory>) -> Result<String> {
        policy::target(&file.url, &self.origin)?;
        let mut state = self.state.lock().unwrap();
        if !state.accepting || self.stop.is_cancelled() {
            return Err(AppError::new("cancelled", "应用正在退出，无法添加下载"));
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
            >= self.config.queue_capacity + 2
        {
            return Err(AppError::new("invalid-input", "下载队列已满，请稍后重试"));
        }
        let permit = self
            .send
            .try_reserve()
            .map_err(|_| AppError::new("invalid-input", "下载队列已满，请稍后重试"))?;
        let (writer, reservation) = directory.reserve(&file.filename).map_err(storage)?;
        // Keep one identity handle per queued file; clone a writer only while executing.
        drop(writer);
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

async fn run(owner: Arc<Inner>, job: Job) {
    let Job {
        id,
        url,
        reservation,
        cancel,
    } = job;
    let permit = tokio::select! {
        biased;
        _ = cancel.cancelled() => None,
        result = owner.slots.clone().acquire_owned() => result.ok(),
    };
    let file = reservation.writer().map(tokio::fs::File::from_std);
    let mut file = match file {
        Ok(file) => file,
        Err(error) => {
            let cleanup = tokio::task::spawn_blocking(move || reservation.cleanup()).await;
            owner.update(&id, |task| {
                task.state = TaskState::Failed;
                task.error = Some(match cleanup {
                    Ok(Ok(())) => format!("无法打开下载文件：{error}"),
                    _ => format!("无法打开下载文件：{error}；清理失败，请检查下载目录"),
                });
            });
            return;
        }
    };
    let result = if permit.is_none() {
        Err(AppError::new("cancelled", "下载已取消"))
    } else {
        owner.update(&id, |task| task.state = TaskState::Running);
        tokio::select! {
            biased;
            _ = cancel.cancelled() => Err(AppError::new("cancelled", "下载已取消")),
            result = transfer(&owner, &id, &url, &mut file) => result,
        }
    };
    // Pending Tokio file writes must finish and the handle must close before deletion/rename.
    let flushed = file.flush().await.map_err(storage);
    let synced = if result.is_ok() && flushed.is_ok() {
        file.sync_all().await.map_err(storage)
    } else {
        Ok(())
    };
    drop(file.into_std().await);
    let result = result.and(flushed).and(synced);
    let result = if result.is_ok() && !cancel.is_cancelled() {
        tokio::task::spawn_blocking(move || reservation.finish().map_err(storage))
            .await
            .map_err(|_| AppError::new("storage", "保存文件异常终止"))
            .and_then(|result| result)
    } else {
        let cleanup = tokio::task::spawn_blocking(move || reservation.cleanup().map_err(storage))
            .await
            .map_err(|_| AppError::new("storage", "清理文件异常终止"))
            .and_then(|result| result);
        match (result, cleanup) {
            (_, Err(error)) => Err(error),
            (Err(error), Ok(())) => Err(error),
            (Ok(()), Ok(())) => Err(AppError::new("cancelled", "下载已取消")),
        }
    };
    owner.update(&id, |task| match result {
        Ok(filename) => {
            task.filename = filename;
            task.state = TaskState::Completed;
        }
        Err(error) if error.code == "cancelled" => task.state = TaskState::Cancelled,
        Err(error) => {
            task.state = TaskState::Failed;
            task.error = Some(error.message);
        }
    });
    drop(permit);
}

async fn transfer<W: tokio::io::AsyncWrite + Unpin>(
    owner: &Inner,
    id: &str,
    url: &str,
    file: &mut W,
) -> Result<()> {
    let response = tokio::time::timeout(
        owner.config.header_timeout,
        owner
            .client
            .get(url)
            .header("Referer", "https://scgc.video.play/")
            .header("Accept-Encoding", "identity")
            .send(),
    )
    .await
    .map_err(|_| AppError::new("timeout", "视频服务响应超时"))?
    .map_err(network)?;
    if response.status() != 200 {
        return Err(AppError::new(
            "upstream",
            format!("视频下载失败（HTTP {}）", response.status().as_u16()),
        ));
    }
    let kind = response
        .headers()
        .get("content-type")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("")
        .split(';')
        .next()
        .unwrap_or("")
        .trim();
    if !kind.eq_ignore_ascii_case("video/mp4")
        && !kind.eq_ignore_ascii_case("application/octet-stream")
    {
        return Err(AppError::new("upstream", "视频服务返回了非视频内容"));
    }
    if response
        .headers()
        .get("content-encoding")
        .is_some_and(|value| value != "identity")
    {
        return Err(AppError::new("upstream", "视频服务返回了不支持的编码"));
    }
    let total = response.content_length();
    owner.update(id, |task| task.total_bytes = total);
    let mut response = response;
    let mut received = 0;
    let mut emitted = Instant::now();
    while let Some(chunk) = response.chunk().await.map_err(network)? {
        file.write_all(&chunk).await.map_err(storage)?;
        received += chunk.len() as u64;
        if let Some(entry) = owner
            .state
            .lock()
            .unwrap()
            .entries
            .iter_mut()
            .find(|entry| entry.task.id == id && !entry.task.state.is_terminal())
        {
            entry.task.received_bytes = received;
            entry.task.revision += 1;
        }
        if emitted.elapsed() >= Duration::from_millis(100) {
            owner.update(id, |task| task.received_bytes = received);
            emitted = Instant::now();
        }
    }
    file.flush().await.map_err(storage)?;
    // The final byte count is included with the terminal update, without a second progress event.
    if let Some(entry) = owner
        .state
        .lock()
        .unwrap()
        .entries
        .iter_mut()
        .find(|entry| entry.task.id == id && !entry.task.state.is_terminal())
    {
        entry.task.received_bytes = received;
    }
    Ok(())
}
fn storage(error: std::io::Error) -> AppError {
    AppError::new("storage", format!("无法保存或清理下载文件：{error}"))
}
fn network(error: reqwest::Error) -> AppError {
    AppError::new(
        if error.is_timeout() {
            "timeout"
        } else {
            "upstream"
        },
        if error.is_timeout() {
            "视频传输超时，请重试"
        } else {
            "视频传输中断，请重试"
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        pin::Pin,
        task::{Context, Poll},
    };
    use tokio::io::AsyncWrite;

    struct FailedFlush;
    impl AsyncWrite for FailedFlush {
        fn poll_write(
            self: Pin<&mut Self>,
            _: &mut Context<'_>,
            buffer: &[u8],
        ) -> Poll<std::io::Result<usize>> {
            Poll::Ready(Ok(buffer.len()))
        }
        fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Ready(Err(std::io::Error::other("flush failed")))
        }
        fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Ready(Ok(()))
        }
    }

    #[tokio::test]
    async fn propagates_a_sink_flush_failure_after_receiving_the_complete_body() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let origin = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            axum::serve(
                listener,
                axum::Router::new().fallback(|| async {
                    axum::http::Response::builder()
                        .header("Content-Type", "video/mp4")
                        .body(axum::body::Body::from("fixture"))
                        .unwrap()
                }),
            )
            .await
            .unwrap();
        });
        let manager = DownloadManager::new(DownloadConfig {
            upstream_origin: origin.clone(),
            ..DownloadConfig::default()
        })
        .unwrap();
        let error = transfer(
            &manager.inner,
            "absent",
            &format!("{origin}/clip.mp4"),
            &mut FailedFlush,
        )
        .await
        .unwrap_err();
        assert_eq!(error.code, "storage");
        manager.shutdown().await;
        server.abort();
    }
}
