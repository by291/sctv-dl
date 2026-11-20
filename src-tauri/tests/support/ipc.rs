use serde_json::Value;
use tauri::{
    ipc::{CallbackFn, InvokeBody},
    test::{INVOKE_KEY, get_ipc_response},
    webview::InvokeRequest,
};

pub struct CommandInvocation<'a> {
    pub window: &'a tauri::WebviewWindow<tauri::test::MockRuntime>,
    pub command: &'a str,
    pub body: Value,
    pub origin: &'a str,
}

/// Returns the trusted asset origin used by the current desktop platform.
pub fn local_origin() -> &'static str {
    if cfg!(windows) {
        "http://tauri.localhost"
    } else {
        "tauri://localhost"
    }
}

/// Executes a command through Tauri's IPC parsing and capability enforcement.
pub fn invoke(invocation: CommandInvocation<'_>) -> Result<Value, Value> {
    get_ipc_response(
        invocation.window,
        InvokeRequest {
            cmd: invocation.command.into(),
            callback: CallbackFn(0),
            error: CallbackFn(1),
            url: invocation.origin.parse().unwrap(),
            body: InvokeBody::Json(invocation.body),
            headers: Default::default(),
            invoke_key: INVOKE_KEY.into(),
        },
    )
    .map(|body| body.deserialize().unwrap())
}

/// Distinguishes a capability rejection from argument validation or business errors.
pub fn assert_permission_denied(result: Result<Value, Value>) {
    let error = result.expect_err("An untrusted command invocation was accepted");
    let message = error
        .as_str()
        .expect("IPC access must fail at the capability boundary");

    assert!(
        message.contains("not allowed"),
        "Unexpected IPC error: {message}"
    );
}
