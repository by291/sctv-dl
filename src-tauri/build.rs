fn main() {
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(
        tauri_build::AppManifest::new().commands(&[
            "list_programmes",
            "list_programme_dates",
            "list_programme_contents",
            "cancel_request",
        ]),
    ))
    .expect("failed to build Tauri application permissions");
}
