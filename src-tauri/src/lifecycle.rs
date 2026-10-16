use std::{
    future::Future,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};
use tauri::{AppHandle, Manager, Runtime};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};
use tokio::sync::{OwnedRwLockReadGuard, RwLock};

use crate::{
    downloads::DownloadManager,
    error::{AppError, Result},
};

#[derive(Default)]
pub struct ExitController {
    operations: Arc<RwLock<()>>,
    closing: AtomicBool,
    committed: AtomicBool,
}

impl ExitController {
    pub async fn enter(&self) -> Result<OwnedRwLockReadGuard<()>> {
        if self.closing.load(Ordering::SeqCst) {
            return Err(closing());
        }
        let guard = self.operations.clone().read_owned().await;
        if self.closing.load(Ordering::SeqCst) {
            return Err(closing());
        }
        Ok(guard)
    }

    pub fn begin(self: &Arc<Self>) -> Option<ExitRequest> {
        self.closing
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .ok()?;
        Some(ExitRequest {
            controller: self.clone(),
        })
    }

    pub fn committed(&self) -> bool {
        self.committed.load(Ordering::SeqCst)
    }
}

fn closing() -> AppError {
    AppError::new("cancelled", "应用正在退出")
}

pub struct ExitRequest {
    controller: Arc<ExitController>,
}

impl ExitRequest {
    pub async fn complete<F, Fut>(self, downloads: &DownloadManager, confirm: F) -> bool
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = bool>,
    {
        // Existing picker/prepare/save work must settle before the final task snapshot.
        let _operations = self.controller.operations.clone().write_owned().await;
        if downloads.has_active() && !confirm().await {
            return false;
        }
        downloads.shutdown().await;
        self.controller.committed.store(true, Ordering::SeqCst);
        true
    }
}

impl Drop for ExitRequest {
    fn drop(&mut self) {
        if !self.controller.committed() {
            self.controller.closing.store(false, Ordering::SeqCst);
        }
    }
}

pub fn request_exit<R: Runtime>(app: &AppHandle<R>) {
    let controller = app.state::<Arc<ExitController>>();
    let Some(request) = controller.begin() else {
        return;
    };
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let downloads = app.state::<DownloadManager>();
        if request
            .complete(&downloads, || async {
                let Some(window) = app.get_webview_window("main") else {
                    return false;
                };
                let (send, receive) = tokio::sync::oneshot::channel();
                app.dialog()
                    .message("还有下载任务正在进行。退出将取消这些任务，是否继续？")
                    .title("退出 SCTV DL")
                    .parent(&window)
                    .buttons(MessageDialogButtons::OkCancelCustom(
                        "取消下载并退出".into(),
                        "继续下载".into(),
                    ))
                    .show(move |accepted| {
                        let _ = send.send(accepted);
                    });
                receive.await.unwrap_or(false)
            })
            .await
        {
            app.exit(0);
        }
    });
}

pub fn install_menu<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<()> {
    use tauri::menu::{Menu, MenuItem, MenuItemKind, PredefinedMenuItem};
    let menu = Menu::default(app)?;
    let quit_text = PredefinedMenuItem::quit(app, None)?.text()?;
    let mut replaced = false;
    for item in menu.items()? {
        if let MenuItemKind::Submenu(submenu) = item {
            for (index, item) in submenu.items()?.into_iter().enumerate() {
                if let MenuItemKind::Predefined(item) = item
                    && item.text()? == quit_text
                {
                    // Predefined IDs are instance-specific. Match the platform-provided Quit label.
                    // macOS's predefined Quit invokes terminate: without ExitRequested.
                    replaced = true;
                    submenu.remove_at(index)?;
                    submenu.insert(
                        &MenuItem::with_id(app, "quit", item.text()?, true, Some("CmdOrCtrl+Q"))?,
                        index,
                    )?;
                }
            }
        }
    }
    if cfg!(any(target_os = "macos", target_os = "windows")) && !replaced {
        return Err(std::io::Error::other("default Quit menu was not found").into());
    }
    app.set_menu(menu)?;
    app.on_menu_event(|app, event| {
        if event.id().as_ref() == "quit" {
            request_exit(app);
        }
    });
    Ok(())
}
