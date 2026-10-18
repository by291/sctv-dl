use std::{sync::Arc, time::Duration};

use tauri::{AppHandle, Manager, Runtime};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};

use super::{ExitController, ExitPreparation};
use crate::downloads::DownloadManager;

pub fn request_exit<R: Runtime>(app: &AppHandle<R>) {
    let controller = app.state::<Arc<ExitController>>();
    let Some(request) = controller.begin() else {
        return;
    };

    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let downloads = app.state::<DownloadManager>();
        let prepare = app.state::<ExitPreparation>();
        if request
            .complete_with_recovery(
                &downloads,
                prepare.prepare(Duration::from_secs(5)),
                |saved| confirm_exit(&app, saved, downloads.has_active()),
                |_| confirm_force_exit(&app),
            )
            .await
        {
            app.exit(0);
        }
    });
}

async fn confirm_exit<R: Runtime>(app: &AppHandle<R>, saved: bool, active: bool) -> bool {
    let Some(window) = app.get_webview_window("main") else {
        return false;
    };

    let message = match (saved, active) {
        (false, true) => {
            "部分设置或观看进度未能保存，且还有下载任务。退出将放弃未保存的数据并暂停下载，是否继续？"
        }
        (false, false) => "部分设置或观看进度未能保存。退出将放弃这些数据，是否继续？",
        _ => "还有下载任务正在进行。退出将保存进度并暂停下载，下次打开后可手动继续，是否退出？",
    };

    confirm_dialog(app, &window, message, "仍然退出").await
}

async fn confirm_force_exit<R: Runtime>(app: &AppHandle<R>) -> bool {
    let Some(window) = app.get_webview_window("main") else {
        return false;
    };

    confirm_dialog(
        app,
        &window,
        "部分下载进度未能安全保存。强制退出会保留现有临时文件，但下次可能需要重新下载，是否强制退出？",
        "强制退出",
    )
    .await
}

async fn confirm_dialog<R: Runtime>(
    app: &AppHandle<R>,
    window: &tauri::WebviewWindow<R>,
    message: &str,
    accept: &str,
) -> bool {
    let (send, receive) = tokio::sync::oneshot::channel();
    app.dialog()
        .message(message)
        .title("退出 SCTV DL")
        .parent(window)
        .buttons(MessageDialogButtons::OkCancelCustom(
            accept.into(),
            "返回应用".into(),
        ))
        .show(move |accepted| {
            let _ = send.send(accepted);
        });

    // A dismissed/lost dialog must leave the application open.
    receive.await.unwrap_or(false)
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
