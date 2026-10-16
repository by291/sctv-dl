use axum::Router;
use tokio::{net::TcpListener, task::JoinHandle};

pub struct Stub {
    pub origin: String,
    task: JoinHandle<()>,
}

impl Drop for Stub {
    fn drop(&mut self) {
        self.task.abort();
    }
}

pub async fn serve(router: Router) -> Stub {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let task = tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });

    Stub { origin, task }
}
