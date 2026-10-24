import Foundation

/// Keeps security-scoped access alive while playback, export or reveal retains this lease.
/// The release callback runs exactly once at deinitialization, after the last owner releases it.
public final class LocalFileLease: Sendable {
    public let url: URL
    private let release: @Sendable () -> Void

    public init(url: URL, release: @escaping @Sendable () -> Void = {}) throws {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        self.url = url
        self.release = release
    }

    deinit { release() }
}

public protocol DownloadedFileAccess: Sendable {
    /// Opens a published local file and verifies its current attempt and file identity.
    /// The caller retains the returned lease for the entire operation. Missing media, changed
    /// identity, inaccessible destinations and storage failures throw; there is no online fallback.
    func open(_ taskID: UUID) async throws -> LocalFileLease
}
