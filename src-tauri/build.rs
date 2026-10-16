fn main() {
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(
        tauri_build::AppManifest::new().commands(&[
            "list_programmes",
            "list_programme_dates",
            "list_programme_contents",
            "cancel_request",
            "start_downloads",
            "list_downloads",
            "subscribe_downloads",
            "unsubscribe_downloads",
            "cancel_download",
            "get_download_directory",
            "choose_download_directory",
        ]),
    ))
    .expect("failed to build Tauri application permissions");
}
