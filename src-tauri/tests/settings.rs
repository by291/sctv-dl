use sctv_dl_desktop_lib::{error::ErrorCode, settings::installation_id};
use serde_json::{Value, json};
use tauri::test::{mock_builder, mock_context, noop_assets};
use tauri_plugin_store::StoreExt;
use uuid::Uuid;

#[test]
fn propagates_identity_save_failures_without_overwriting_the_existing_store() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("desktop.json");
    let original = br#"{"unrelated":true}"#;
    std::fs::write(&path, original).unwrap();
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .build(mock_context(noop_assets()))
        .unwrap();
    let store = app
        .store_builder(&path)
        .disable_auto_save()
        .serialize(|_| Err(std::io::Error::other("injected save failure").into()))
        .build()
        .unwrap();
    assert_eq!(
        installation_id(&store).unwrap_err().code,
        ErrorCode::Storage
    );
    assert_eq!(std::fs::read(&path).unwrap(), original);
}

#[test]
fn failed_directory_save_rolls_back_memory_and_preserves_persisted_identity() {
    use sctv_dl_desktop_lib::settings::{download_directory, save_download_directory};
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("desktop.json");
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .build(mock_context(noop_assets()))
        .unwrap();
    let store = app
        .store_builder(&path)
        .disable_auto_save()
        .serialize(|values| {
            if values.contains_key("downloadDirectory") {
                Err(std::io::Error::other("injected save failure").into())
            } else {
                Ok(serde_json::to_vec(values)?)
            }
        })
        .build()
        .unwrap();
    let identity = installation_id(&store).unwrap();
    let original = std::fs::read(&path).unwrap();
    assert_eq!(
        save_download_directory(&store, root.path())
            .unwrap_err()
            .code,
        ErrorCode::Storage
    );
    assert!(download_directory(&store).unwrap().is_none());
    assert_eq!(std::fs::read(&path).unwrap(), original);
    assert_eq!(store.get("installationId").unwrap(), identity);
}

#[test]
fn stores_download_directories_privately_and_rejects_missing_locations() {
    use sctv_dl_desktop_lib::settings::{download_directory, save_download_directory};
    let directory = tempfile::tempdir().unwrap();
    let destination = directory.path().join("downloads");
    std::fs::create_dir(&destination).unwrap();
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .build(mock_context(noop_assets()))
        .unwrap();
    let store = app
        .store_builder(directory.path().join("desktop.json"))
        .disable_auto_save()
        .build()
        .unwrap();
    let identity = installation_id(&store).unwrap();
    assert!(download_directory(&store).unwrap().is_none());
    save_download_directory(&store, &destination).unwrap();
    assert_eq!(
        download_directory(&store).unwrap(),
        Some(destination.canonicalize().unwrap())
    );
    assert_eq!(store.get("installationId").unwrap(), identity);
    assert!(store.get("preferences").is_none());
    assert!(save_download_directory(&store, &directory.path().join("missing")).is_err());
    std::fs::remove_dir(&destination).unwrap();
    assert_eq!(
        download_directory(&store).unwrap_err().code,
        ErrorCode::Storage
    );
}

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
    assert_eq!(
        installation_id(&corrupt).unwrap_err().code,
        ErrorCode::Storage
    );
    assert_eq!(std::fs::read(&corrupt_path).unwrap(), b"not-json");
    let blocking_file = directory.path().join("file");
    std::fs::write(&blocking_file, b"occupied").unwrap();
    let unwritable = app
        .store_builder(blocking_file.join("desktop.json"))
        .disable_auto_save()
        .build()
        .unwrap();
    assert_eq!(
        installation_id(&unwritable).unwrap_err().code,
        ErrorCode::Storage
    );
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
    assert_eq!(
        installation_id(&store).unwrap_err().code,
        ErrorCode::Storage
    );
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

#[test]
fn preferences_normalize_like_shared_schema_without_exposing_private_values() {
    use sctv_dl_desktop_lib::settings::{load_preferences, save_preferences};
    let root = tempfile::tempdir().unwrap();
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .build(mock_context(noop_assets()))
        .unwrap();
    let store = app
        .store_builder(root.path().join("desktop.json"))
        .disable_auto_save()
        .build()
        .unwrap();
    let identity = installation_id(&store).unwrap();
    store.set("downloadDirectory", json!(root.path().to_str().unwrap()));
    store.set("preferences", json!({"theme":"dark", "quality":"invalid", "favourites":["1", 2, "../3", "1", "004"], "installationId":"leak"}));
    let snapshot = serde_json::to_value(load_preferences(Ok(&store))).unwrap();
    assert_eq!(
        snapshot,
        json!({"value":{"theme":"dark","quality":"standard","favourites":["1","004"]}, "persisted":true})
    );
    save_preferences(
        &store,
        json!({"theme":"light", "quality":"smooth", "favourites":["8"]}),
    )
    .unwrap();
    let reloaded = app
        .store_builder(root.path().join("desktop.json"))
        .disable_auto_save()
        .create_new()
        .build()
        .unwrap();
    assert_eq!(installation_id(&reloaded).unwrap(), identity);
    assert_eq!(
        serde_json::to_value(load_preferences(Ok(&reloaded))).unwrap()["value"],
        json!({"theme":"light","quality":"smooth","favourites":["8"]})
    );
    assert_eq!(
        reloaded.get("downloadDirectory").unwrap(),
        root.path().to_str().unwrap()
    );
}

#[test]
fn preference_errors_keep_defaults_usable_and_failed_writes_preserve_saved_values() {
    use sctv_dl_desktop_lib::{
        error::AppError,
        settings::{load_preferences, save_preferences},
    };
    let snapshot = serde_json::to_value(load_preferences::<tauri::test::MockRuntime>(Err(
        AppError::new(ErrorCode::Storage, "denied"),
    )))
    .unwrap();
    assert_eq!(
        snapshot,
        json!({"value":{"theme":"system","quality":"standard","favourites":[]}, "persisted":false})
    );
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("desktop.json");
    std::fs::write(
        &path,
        br#"{"preferences":{"theme":"dark"},"installationId":"keep"}"#,
    )
    .unwrap();
    let original = std::fs::read(&path).unwrap();
    let app = mock_builder()
        .plugin(tauri_plugin_store::Builder::default().build())
        .build(mock_context(noop_assets()))
        .unwrap();
    let store = app
        .store_builder(&path)
        .disable_auto_save()
        .serialize(|_| Err(std::io::Error::other("injected write failure").into()))
        .build()
        .unwrap();
    assert_eq!(
        save_preferences(&store, json!({"theme":"light"}))
            .unwrap_err()
            .code,
        ErrorCode::Storage
    );
    assert_eq!(std::fs::read(&path).unwrap(), original);
    assert_eq!(store.get("preferences").unwrap(), json!({"theme":"dark"}));
}
