fn main() {
    let mut attributes = tauri_build::Attributes::new();
    if std::env::var("TARGET").is_ok_and(|target| target.ends_with("windows-msvc")) {
        // Tauri embeds application resources only into binaries. Test executables also
        // need Common Controls v6 before loading the native dialog dependency.
        println!("cargo:rustc-link-arg=/MANIFEST:EMBED");
        println!(
            "cargo:rustc-link-arg=/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
        );
        // The linker now embeds the same dependency for every executable; avoid
        // adding a second manifest resource to the application binary.
        attributes = attributes
            .windows_attributes(tauri_build::WindowsAttributes::new_without_app_manifest());
    }

    tauri_build::try_build(
        attributes.app_manifest(tauri_build::AppManifest::new().commands(&[
            "read_programme_cache",
            "write_programme_cache",
            "read_archive_browse_state",
            "write_archive_browse_state",
            "clear_programme_cache",
            "list_history",
            "begin_history",
            "record_history",
            "end_history",
            "remove_history",
            "clear_history",
            "subscribe_history",
            "unsubscribe_history",
            "list_programmes",
            "list_programme_dates",
            "list_programme_contents",
            "cancel_request",
            "get_download_snapshot",
            "subscribe_download_events",
            "unsubscribe_download_events",
            "act_on_download",
            "open_local_playback",
            "start_downloads",
            "list_downloads",
            "subscribe_downloads",
            "unsubscribe_downloads",
            "cancel_download",
            "get_download_directory",
            "choose_download_directory",
            "load_settings",
            "save_settings",
            "open_playback",
            "close_playback",
            "subscribe_exit",
            "unsubscribe_exit",
            "complete_exit_preparation",
        ])),
    )
    .expect("failed to build Tauri application permissions");
}
