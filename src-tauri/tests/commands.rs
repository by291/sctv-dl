#[path = "support/ipc.rs"]
mod ipc;

use axum::{Json, Router, http::Uri};
use ipc::{CommandInvocation, assert_permission_denied, invoke, local_origin};
use sctv_dl_desktop_lib::{
    error::{AppError, ErrorCode},
    programmes::{Deadlines, ProgrammeService},
    state::AppState,
};
use serde_json::{Value, json};
use tauri::test::mock_builder;
use uuid::Uuid;

fn app(state: AppState) -> tauri::App<tauri::test::MockRuntime> {
    mock_builder()
        .manage(state)
        .invoke_handler(sctv_dl_desktop_lib::create_command_handler())
        .build(tauri::generate_context!(test = true))
        .unwrap()
}

async fn programme_response(uri: Uri) -> Json<Value> {
    let data = if uri.query().is_some() {
        json!({ "records": [{ "id": 1, "name": "News" }] })
    } else if uri.path().contains("contents") {
        json!([{ "id": 3, "title": "Clip" }])
    } else {
        json!([{ "id": 2, "date": "2026-10-15" }])
    };

    Json(json!({ "rs": 200, "data": data }))
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn routes_native_commands_to_services_and_enforces_main_window_local_permissions() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        axum::serve(listener, Router::new().fallback(programme_response))
            .await
            .unwrap();
    });

    let app = app(AppState::new(Ok(ProgrammeService::new(
        &origin,
        Uuid::new_v4().to_string(),
        Deadlines::default(),
    )
    .unwrap())));
    let main = tauri::WebviewWindowBuilder::new(&app, "main", Default::default())
        .build()
        .unwrap();
    let secondary = tauri::WebviewWindowBuilder::new(&app, "secondary", Default::default())
        .build()
        .unwrap();
    let local = local_origin();

    for (command, args, expected) in [
        (
            "list_programmes",
            json!({}),
            json!([{"id": "1", "name": "News", "cover": null}]),
        ),
        (
            "list_programme_dates",
            json!({"programmeId": "1"}),
            json!([{"id": "2", "date": "2026-10-15"}]),
        ),
        (
            "list_programme_contents",
            json!({
                "programmeId": "1",
                "dateId": "2"
            }),
            json!([{
                "id": "3",
                "title": "Clip",
                "cover": null,
                "video": null,
                "smoothVideo": null,
                "publishedAt": null
            }]),
        ),
        ("cancel_request", json!({}), Value::Null),
    ] {
        let mut args = args;
        args["requestId"] = json!(Uuid::new_v4().to_string());

        assert_eq!(
            invoke(CommandInvocation {
                window: &main,
                command,
                body: args.clone(),
                origin: local,
            })
            .unwrap(),
            expected
        );
        assert_permission_denied(invoke(CommandInvocation {
            window: &secondary,
            command,
            body: args.clone(),
            origin: local,
        }));
        assert_permission_denied(invoke(CommandInvocation {
            window: &main,
            command,
            body: args,
            origin: "https://external.invalid",
        }));
    }

    let denied_store = invoke(CommandInvocation {
        window: &main,
        command: "plugin:store|load",
        body: json!({"path": "arbitrary.json"}),
        origin: local,
    })
    .unwrap_err();
    assert!(denied_store.as_str().unwrap().contains("not allowed"));

    let invalid = invoke(CommandInvocation {
        window: &main,
        command: "list_programme_dates",
        body: json!({
            "programmeId": "../1",
            "requestId": Uuid::new_v4().to_string()
        }),
        origin: local,
    })
    .unwrap_err();
    assert_eq!(invalid["code"], "invalid-input");

    server.abort();
}

#[test]
fn surfaces_identity_storage_failure_without_starting_upstream_work() {
    let app = app(AppState::new(Err(AppError::new(
        ErrorCode::Storage,
        "Storage unavailable",
    ))));
    let main = tauri::WebviewWindowBuilder::new(&app, "main", Default::default())
        .build()
        .unwrap();
    let local = local_origin();

    let error = invoke(CommandInvocation {
        window: &main,
        command: "list_programmes",
        body: json!({"requestId": Uuid::new_v4().to_string()}),
        origin: local,
    })
    .unwrap_err();
    assert_eq!(
        error,
        json!({"code": "storage", "message": "Storage unavailable"})
    );
}
