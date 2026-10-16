use tauri::{State, ipc::Channel};

use crate::lifecycle::ExitPreparation;

#[tauri::command]
pub fn subscribe_exit(
    preparation: State<'_, ExitPreparation>,
    on_event: Channel<String>,
) -> String {
    preparation.subscribe(move |id| on_event.send(id).is_ok())
}

#[tauri::command]
pub fn unsubscribe_exit(preparation: State<'_, ExitPreparation>, subscription_id: String) {
    preparation.unsubscribe(&subscription_id);
}

#[tauri::command]
pub fn complete_exit_preparation(
    preparation: State<'_, ExitPreparation>,
    request_id: String,
    saved: bool,
) {
    preparation.complete(&request_id, saved);
}
