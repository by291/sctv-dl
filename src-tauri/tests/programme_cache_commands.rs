#[path = "support/ipc.rs"]
mod ipc;

use std::sync::Arc;

use sctv_dl_desktop_lib::{
    commands, lifecycle::ExitController, programme_cache::ProgrammeCacheService,
};
use serde_json::json;
use tauri::test::mock_builder;

use ipc::{invoke, local_origin};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn cache_commands_reject_remote_and_secondary_windows_and_bad_keys() {
    let root = tempfile::tempdir().unwrap();
    let app = mock_builder()
        .manage(Arc::new(ExitController::default()))
        .manage(ProgrammeCacheService::open(root.path().join("cache")).await)
        .invoke_handler(tauri::generate_handler![
            commands::read_programme_cache,
            commands::write_programme_cache,
            commands::read_archive_browse_state,
            commands::write_archive_browse_state,
            commands::clear_programme_cache
        ])
        .build(tauri::generate_context!(test = true))
        .unwrap();
    let main = tauri::WebviewWindowBuilder::new(&app, "main", Default::default())
        .build()
        .unwrap();
    let secondary = tauri::WebviewWindowBuilder::new(&app, "secondary", Default::default())
        .build()
        .unwrap();
    let origin = local_origin();

    let initial = invoke(
        &main,
        "read_programme_cache",
        json!({"key": {"kind": "catalogue"}}),
        origin,
    )
    .unwrap();
    let body = json!({
        "key": { "kind": "catalogue" },
        "payload": { "kind": "catalogue", "items": [] },
        "expectedEpoch": initial["epoch"],
        "programmeId": "1",
        "value": {
            "programmeId": "1",
            "dateId": null,
            "date": null,
            "sort": "asc",
            "scrollY": 0,
            "visitedAt": "2026-10-17T00:00:00.000Z"
        }
    });

    for command in [
        "read_programme_cache",
        "write_programme_cache",
        "read_archive_browse_state",
        "write_archive_browse_state",
        "clear_programme_cache",
    ] {
        assert!(invoke(&secondary, command, body.clone(), origin).is_err());
        assert!(invoke(&main, command, body.clone(), "https://external.invalid").is_err());
    }

    assert_eq!(
        invoke(
            &main,
            "read_programme_cache",
            json!({
                "key": {
                    "kind": "dates",
                    "programmeId": "../private"
                }
            }),
            origin
        )
        .unwrap_err()["code"],
        "invalid-input"
    );

    assert_eq!(
        invoke(&main, "write_programme_cache", body.clone(), origin).unwrap()["persisted"],
        true
    );

    // Older cache records may omit optional fields; unknown metadata remains tolerated.
    for (payload, expected_items) in [
        (
            json!({
                "kind": "catalogue",
                "items": [{
                    "id": "1",
                    "name": "News",
                    "future": true
                }]
            }),
            json!([{ "id": "1", "name": "News", "cover": null }]),
        ),
        (
            json!({
                "kind": "dates",
                "programmeId": "1",
                "items": [{ "id": "2", "date": "2026-10-17" }]
            }),
            json!([{ "id": "2", "date": "2026-10-17" }]),
        ),
        (
            json!({
                "kind": "contents",
                "programmeId": "1",
                "dateId": "2",
                "items": [{ "id": "3", "title": "Evening" }]
            }),
            json!([{
                "id": "3",
                "title": "Evening",
                "cover": null,
                "video": null,
                "smoothVideo": null,
                "publishedAt": null
            }]),
        ),
    ] {
        let written = invoke(
            &main,
            "write_programme_cache",
            json!({ "payload": payload, "expectedEpoch": initial["epoch"] }),
            origin,
        )
        .unwrap();

        assert_eq!(written["persisted"], true);
        assert_eq!(written["snapshot"]["items"], expected_items);
    }

    for invalid_item in [
        json!({ "id": "../3", "title": "Invalid ID" }),
        json!({ "id": "3", "title": "Invalid URL", "video": "file:///private.mp4" }),
    ] {
        let error = invoke(
            &main,
            "write_programme_cache",
            json!({
                "expectedEpoch": initial["epoch"],
                "payload": {
                    "kind": "contents",
                    "programmeId": "1",
                    "dateId": "2",
                    "items": [invalid_item]
                }
            }),
            origin,
        )
        .unwrap_err();

        assert_eq!(error["code"], "invalid-input");
    }
}
