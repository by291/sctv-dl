use tauri::{State, ipc::Channel};

use crate::lifecycle::{ExitEvent, ExitPreparation};

/// Binds native exit requests and cancellations to the main frontend.
#[tauri::command]
pub fn subscribe_exit(
    preparation: State<'_, ExitPreparation>,
    on_event: Channel<ExitEvent>,
) -> String {
    preparation.subscribe(move |id| on_event.send(id).is_ok())
}

/// Removes the named frontend exit subscription.
#[tauri::command]
pub fn unsubscribe_exit(preparation: State<'_, ExitPreparation>, subscription_id: String) {
    preparation.unsubscribe(&subscription_id);
}

/// Delivers the save outcome for one native exit attempt.
#[tauri::command]
pub fn complete_exit_preparation(
    preparation: State<'_, ExitPreparation>,
    request_id: String,
    saved: bool,
) {
    preparation.complete(&request_id, saved);
}
