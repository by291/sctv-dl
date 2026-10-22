import SCTVCore

/// The coordinator and presentation layer use the same capability rules.
enum DownloadTransition {
    static func allows(_ action: DownloadAction, in state: DownloadState) -> Bool {
        state.allows(action)
    }
}
