import Foundation

/// A lease keeps security-scoped access alive until the last playback/export owner releases it.
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
    func open(_ taskID: UUID) async throws -> LocalFileLease
}
