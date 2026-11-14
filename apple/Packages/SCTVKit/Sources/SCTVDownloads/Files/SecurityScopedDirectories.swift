import Foundation
import SCTVCore

public enum DownloadFileError: String, LocalizedError, Sendable {
    case unsafePath, missingFile, accessDenied, identityChanged, emptyFile, invalidMedia

    /// Identifies the failure for localized presentation and durable records.
    public var issueCode: DownloadIssueCode {
        switch self {
        case .unsafePath: .unsafePath
        case .missingFile: .missingFile
        case .accessDenied: .accessDenied
        case .identityChanged: .identityChanged
        case .emptyFile: .emptyFile
        case .invalidMedia: .invalidMedia
        }
    }

    public var errorDescription: String? { issueCode.errorDescription }
}

public actor SecurityScopedDirectories {
    private let storage: URL

    public init(storage: URL) { self.storage = storage }

    /// Creates or renews the durable bookmark used by existing download tasks.
    public func authorize(_ directory: URL, replacing existingID: UUID? = nil) throws -> UUID {
        #if os(macOS)
            let access = directory.startAccessingSecurityScopedResource()
            defer { if access { directory.stopAccessingSecurityScopedResource() } }
            let data = try directory.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            let id = existingID ?? UUID()
            try data.write(to: storage.appending(path: id.uuidString), options: .atomic)
            return id
        #else
            throw DownloadFileError.accessDenied
        #endif
    }

    /// Opens the bookmark and holds directory access until the returned lease is released.
    public func open(_ id: UUID) throws -> LocalFileLease {
        #if os(macOS)
            let data = try Data(contentsOf: storage.appending(path: id.uuidString))
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale, url.startAccessingSecurityScopedResource() else {
                throw DownloadFileError.accessDenied
            }
            return try LocalFileLease(url: url) { url.stopAccessingSecurityScopedResource() }
        #else
            throw DownloadFileError.accessDenied
        #endif
    }
}

func confinedFile(_ relative: String, under root: URL) throws -> URL {
    guard !relative.isEmpty, !relative.hasPrefix("/"),
        !relative.split(separator: "/").contains("..")
    else { throw DownloadFileError.unsafePath }
    let base = root.standardizedFileURL.resolvingSymlinksInPath()
    var componentURL = base
    for component in relative.split(separator: "/") {
        componentURL.append(path: String(component))
        let attributes = try? FileManager.default.attributesOfItem(atPath: componentURL.path)
        guard attributes?[.type] as? FileAttributeType != .typeSymbolicLink else {
            throw DownloadFileError.unsafePath
        }
    }
    let file = base.appending(path: relative).standardizedFileURL.resolvingSymlinksInPath()
    guard file.path.hasPrefix(base.path + "/") else { throw DownloadFileError.unsafePath }
    return file
}
