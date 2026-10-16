use tauri::State;

use crate::{
    error::Result,
    programmes::{Programme, ProgrammeContent, ProgrammeDate},
    state::AppState,
};

#[tauri::command]
pub async fn list_programmes(
    state: State<'_, AppState>,
    request_id: String,
) -> Result<Vec<Programme>> {
    let request = state.requests.register(&request_id)?;
    request
        .run(async {
            state
                .programmes
                .as_ref()
                .map_err(Clone::clone)?
                .programmes()
                .await
        })
        .await
        .map_err(|error| error.reported("list programmes"))
}

#[tauri::command]
pub async fn list_programme_dates(
    state: State<'_, AppState>,
    programme_id: String,
    request_id: String,
) -> Result<Vec<ProgrammeDate>> {
    let request = state.requests.register(&request_id)?;
    request
        .run(async {
            state
                .programmes
                .as_ref()
                .map_err(Clone::clone)?
                .dates(&programme_id)
                .await
        })
        .await
        .map_err(|error| error.reported("list programme dates"))
}

#[tauri::command]
pub async fn list_programme_contents(
    state: State<'_, AppState>,
    programme_id: String,
    date_id: String,
    request_id: String,
) -> Result<Vec<ProgrammeContent>> {
    let request = state.requests.register(&request_id)?;
    request
        .run(async {
            state
                .programmes
                .as_ref()
                .map_err(Clone::clone)?
                .contents(&programme_id, &date_id)
                .await
        })
        .await
        .map_err(|error| error.reported("list programme contents"))
}

#[tauri::command]
pub fn cancel_request(state: State<'_, AppState>, request_id: String) -> Result<()> {
    state.requests.cancel(&request_id)
}
