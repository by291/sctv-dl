use std::fs;

#[cfg(unix)]
use std::io::Read;

use sctv_dl_desktop_lib::{
    error::{AppError, ErrorCode},
    lifecycle::ExitController,
    settings::DesktopSettings,
};
use serde_json::{Value, json};
use uuid::Uuid;

const IDENTITY: &str = "12345678-9abc-4def-8abc-123456789abc";

#[test]
fn opening_existing_identity_does_not_rewrite_the_document() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("desktop.json");
    let original = format!("{{\n  \"installationId\": \"{IDENTITY}\"\n}}\n");
    fs::write(&path, &original).unwrap();

    let (_, identity) = DesktopSettings::open(&path).unwrap();

    assert_eq!(identity, IDENTITY);
    assert_eq!(fs::read_to_string(&path).unwrap(), original);
}

#[tokio::test]
async fn saving_preferences_replaces_the_document_and_preserves_unrelated_values() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("desktop.json");
    let original = json!({
        "installationId": IDENTITY,
        "preferences": { "theme": "dark" },
        "futureField": ["preserve"]
    });
    let original_bytes = serde_json::to_vec(&original).unwrap();
    fs::write(&path, &original_bytes).unwrap();
    let (settings, _) = DesktopSettings::open(&path).unwrap();
    // Unix keeps the old inode readable. Windows can deny replacement with an open reader.
    #[cfg(unix)]
    let mut existing_reader = fs::File::open(&path).unwrap();
    let controller = ExitController::default();

    let admission = controller.enter_save().await.unwrap();
    settings
        .save(json!({"theme": "light"}), admission)
        .await
        .unwrap();

    #[cfg(unix)]
    {
        let mut previous_bytes = Vec::new();
        existing_reader.read_to_end(&mut previous_bytes).unwrap();
        assert_eq!(previous_bytes, original_bytes);
    }
    let disk: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert_eq!(disk["preferences"]["theme"], "light");
    assert_eq!(disk["futureField"], json!(["preserve"]));
}

#[test]
fn surfaces_identity_creation_errors_without_overwriting_other_files() {
    let root = tempfile::tempdir().unwrap();
    let occupied = root.path().join("occupied");
    fs::write(&occupied, b"other").unwrap();

    let result = DesktopSettings::open(&occupied.join("desktop.json"));

    assert_eq!(result.err().unwrap().code, ErrorCode::Storage);
    assert_eq!(fs::read(&occupied).unwrap(), b"other");
}

#[tokio::test]
async fn directory_reads_reject_a_saved_location_that_has_disappeared() {
    let root = tempfile::tempdir().unwrap();
    let destination = root.path().join("downloads");
    fs::create_dir(&destination).unwrap();
    let path = root.path().join("desktop.json");
    let stored = json!({
        "installationId": IDENTITY,
        "downloadDirectory": destination.to_str().unwrap()
    });
    fs::write(&path, serde_json::to_vec(&stored).unwrap()).unwrap();
    let (settings, _) = DesktopSettings::open(&path).unwrap();

    assert_eq!(
        settings.directory().await.unwrap(),
        Some(destination.canonicalize().unwrap())
    );

    fs::remove_dir(&destination).unwrap();
    assert_eq!(
        settings.directory().await.unwrap_err().code,
        ErrorCode::Storage
    );
}

#[test]
fn creates_and_reloads_one_persisted_installation_identity() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("new-profile").join("desktop.json");

    let (_, first) = DesktopSettings::open(&path).unwrap();

    assert_eq!(Uuid::parse_str(&first).unwrap().get_version_num(), 4);
    let disk: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert_eq!(disk["installationId"], first);
    let (_, reloaded) = DesktopSettings::open(&path).unwrap();
    assert_eq!(reloaded, first);
}

#[test]
fn repairs_invalid_identity_without_removing_other_settings() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("desktop.json");
    let original = json!({
        "installationId": "00000000-0000-4000-0000-000000000000",
        "preferences": { "theme": "dark" }
    });
    fs::write(&path, serde_json::to_vec(&original).unwrap()).unwrap();

    let (_, identity) = DesktopSettings::open(&path).unwrap();

    let parsed = Uuid::parse_str(&identity).unwrap();
    assert_eq!(parsed.get_version_num(), 4);
    assert_eq!(parsed.get_variant(), uuid::Variant::RFC4122);
    let disk: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert_eq!(disk["installationId"], identity);
    assert_eq!(disk["preferences"], json!({"theme": "dark"}));
}

#[test]
fn rejects_corrupt_settings_without_overwriting_them() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("desktop.json");
    fs::write(&path, b"not-json").unwrap();

    let result = DesktopSettings::open(&path);

    assert_eq!(result.err().unwrap().code, ErrorCode::Storage);
    assert_eq!(fs::read(&path).unwrap(), b"not-json");
}

#[tokio::test]
async fn preferences_normalize_like_shared_schema_without_exposing_private_values() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("desktop.json");
    let original = json!({
        "installationId": IDENTITY,
        "downloadDirectory": root.path().to_str().unwrap(),
        "preferences": {
            "theme": "dark",
            "quality": "invalid",
            "favourites": [
                "1",
                2,
                "../3",
                "1",
                "004"
            ],
            "installationId": "leak"
        }
    });
    fs::write(&path, serde_json::to_vec(&original).unwrap()).unwrap();
    let (settings, identity) = DesktopSettings::open(&path).unwrap();
    let controller = ExitController::default();

    let snapshot = serde_json::to_value(settings.load().await).unwrap();

    assert_eq!(
        snapshot,
        json!({
            "value": {
                "theme": "dark",
                "quality": "standard",
                "favourites": ["1", "004"]
            },
            "persisted": true
        })
    );

    let admission = controller.enter_save().await.unwrap();
    settings
        .save(
            json!({
                "theme": "light",
                "quality": "smooth",
                "favourites": ["8"]
            }),
            admission,
        )
        .await
        .unwrap();

    let (reloaded, reloaded_identity) = DesktopSettings::open(&path).unwrap();
    assert_eq!(reloaded_identity, identity);
    assert_eq!(
        reloaded.directory().await.unwrap(),
        Some(root.path().canonicalize().unwrap())
    );
    assert_eq!(
        serde_json::to_value(reloaded.load().await).unwrap()["value"],
        json!({
            "theme": "light",
            "quality": "smooth",
            "favourites": ["8"]
        })
    );
}

#[tokio::test]
async fn unavailable_settings_return_flagged_defaults() {
    let settings = DesktopSettings::unavailable(AppError::new(ErrorCode::Storage, "denied"));

    let snapshot = serde_json::to_value(settings.load().await).unwrap();

    assert_eq!(
        snapshot,
        json!({
            "value": {
                "theme": "system",
                "quality": "standard",
                "favourites": []
            },
            "persisted": false
        })
    );
}

#[tokio::test]
async fn failed_replacement_leaves_settings_cache_usable_and_allows_a_retry() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("desktop.json");
    let backup = root.path().join("original.json");
    let original = json!({
        "installationId": IDENTITY,
        "preferences": {"theme": "dark"}
    });
    fs::write(&path, serde_json::to_vec(&original).unwrap()).unwrap();
    let (settings, _) = DesktopSettings::open(&path).unwrap();
    let controller = ExitController::default();

    fs::rename(&path, &backup).unwrap();
    fs::create_dir(&path).unwrap();

    let admission = controller.enter_save().await.unwrap();
    let failed = settings.save(json!({"theme": "light"}), admission).await;

    assert_eq!(failed.unwrap_err().code, ErrorCode::Storage);
    assert_eq!(
        serde_json::to_value(settings.load().await).unwrap()["value"]["theme"],
        "dark"
    );
    let disk: Value = serde_json::from_slice(&fs::read(&backup).unwrap()).unwrap();
    assert_eq!(disk, original);

    fs::remove_dir(&path).unwrap();
    fs::rename(&backup, &path).unwrap();
    let admission = controller.enter_save().await.unwrap();
    settings
        .save(json!({"theme": "light"}), admission)
        .await
        .unwrap();
    let (reloaded, _) = DesktopSettings::open(&path).unwrap();
    assert_eq!(
        serde_json::to_value(reloaded.load().await).unwrap()["value"]["theme"],
        "light"
    );
}

#[cfg(unix)]
#[tokio::test]
async fn sync_failure_keeps_the_replaced_preferences_and_a_later_save_confirms_durability() {
    use std::os::unix::fs::PermissionsExt;

    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("desktop.json");
    let (settings, _) = DesktopSettings::open(&path).unwrap();
    let controller = ExitController::default();
    let submitted = json!({"theme": "light"});
    let admission = controller.enter_save().await.unwrap();

    // Search/write access allows replacement without permitting the final directory sync.
    let original_permissions = fs::metadata(root.path()).unwrap().permissions();
    fs::set_permissions(root.path(), fs::Permissions::from_mode(0o300)).unwrap();
    if fs::File::open(root.path()).is_ok() {
        // Privileged runners may bypass these permission bits.
        fs::set_permissions(root.path(), original_permissions).unwrap();
        return;
    }

    let saved = settings.save(submitted.clone(), admission).await;
    fs::set_permissions(root.path(), original_permissions).unwrap();

    assert_eq!(saved.unwrap_err().code, ErrorCode::Storage);
    let snapshot = serde_json::to_value(settings.load().await).unwrap();
    assert_eq!(snapshot["value"]["theme"], "light");
    assert_eq!(snapshot["persisted"], false);
    let disk: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert_eq!(disk["preferences"]["theme"], "light");

    let admission = controller.enter_save().await.unwrap();
    settings.save(submitted, admission).await.unwrap();
    let snapshot = serde_json::to_value(settings.load().await).unwrap();
    assert_eq!(snapshot["persisted"], true);
}
