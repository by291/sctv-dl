use sctv_dl_desktop_lib::settings::installation_id;
use serde_json::{Value, json};
use tauri::test::{mock_builder, mock_context, noop_assets};
use tauri_plugin_store::StoreExt;
use uuid::Uuid;

#[test]
fn creates_and_reloads_one_persisted_installation_identity() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("desktop.json");
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .build(mock_context(noop_assets()))
        .unwrap();
    let store = app
        .store_builder(&path)
        .disable_auto_save()
        .build()
        .unwrap();
    let first = installation_id(&store).unwrap();
    assert_eq!(Uuid::parse_str(&first).unwrap().get_version_num(), 4);
    let disk: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    assert_eq!(disk["installationId"], first);
    let reloaded = app
        .store_builder(&path)
        .disable_auto_save()
        .create_new()
        .build()
        .unwrap();
    assert_eq!(installation_id(&reloaded).unwrap(), first);
}

#[test]
fn repairs_invalid_identity_without_removing_other_settings() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("desktop.json");
    std::fs::write(
        &path,
        serde_json::to_vec(&json!({"installationId":"00000000-0000-4000-0000-000000000000", "preferences":{"theme":"dark"}}))
            .unwrap(),
    )
    .unwrap();
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .build(mock_context(noop_assets()))
        .unwrap();
    let store = app
        .store_builder(&path)
        .disable_auto_save()
        .build()
        .unwrap();
    let id = installation_id(&store).unwrap();
    assert_eq!(Uuid::parse_str(&id).unwrap().get_version_num(), 4);
    assert_eq!(
        Uuid::parse_str(&id).unwrap().get_variant(),
        uuid::Variant::RFC4122
    );
    let disk: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    assert_eq!(disk["preferences"], json!({"theme":"dark"}));
}

#[test]
fn surfaces_storage_read_errors_instead_of_using_an_ephemeral_identity() {
    let directory = tempfile::tempdir().unwrap();
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .build(mock_context(noop_assets()))
        .unwrap();
    let corrupt_path = directory.path().join("corrupt.json");
    std::fs::write(&corrupt_path, b"not-json").unwrap();
    let corrupt = app
        .store_builder(&corrupt_path)
        .disable_auto_save()
        .build()
        .unwrap();
    assert_eq!(installation_id(&corrupt).unwrap_err().code, "storage");
    assert_eq!(std::fs::read(&corrupt_path).unwrap(), b"not-json");
    let blocking_file = directory.path().join("file");
    std::fs::write(&blocking_file, b"occupied").unwrap();
    let unwritable = app
        .store_builder(blocking_file.join("desktop.json"))
        .disable_auto_save()
        .build()
        .unwrap();
    assert_eq!(installation_id(&unwritable).unwrap_err().code, "storage");
}

#[test]
fn preserves_corrupt_storage_after_the_application_exits() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("corrupt.json");
    std::fs::write(&path, b"not-json").unwrap();
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .build(mock_context(noop_assets()))
        .unwrap();
    let store = app
        .store_builder(&path)
        .disable_auto_save()
        .build()
        .unwrap();
    assert_eq!(installation_id(&store).unwrap_err().code, "storage");
    let window = tauri::WebviewWindowBuilder::new(&app, "main", Default::default())
        .build()
        .unwrap();
    app.run(move |_, event| {
        if matches!(event, tauri::RunEvent::Ready) {
            window.close().unwrap();
        }
    });
    assert_eq!(std::fs::read(&path).unwrap(), b"not-json");
}
