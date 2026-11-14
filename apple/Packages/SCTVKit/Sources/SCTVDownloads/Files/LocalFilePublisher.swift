@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import SCTVCore

public actor LocalFilePublisher: FilePublisher {
    private static let filenameComponentLimit = 255
    private static let legacyTitleLimit = 90
    private static let digestChunkSize = 256 * 1024

    private let staging: URL
    private let managed: URL
    private let copyFile: @Sendable (URL, URL) throws -> Void
    private let isPlayable: @Sendable (URL) async throws -> Bool
    private let directories: SecurityScopedDirectories

    public init(
        staging: URL, managed: URL, directories: SecurityScopedDirectories,
        isPlayable: @escaping @Sendable (URL) async throws -> Bool = {
            try await AVURLAsset(url: $0).load(.isPlayable)
        },
        copyFile: @escaping @Sendable (URL, URL) throws -> Void = {
            try FileManager.default.copyItem(at: $0, to: $1)
        }
    ) throws {
        self.isPlayable = isPlayable
        self.copyFile = copyFile
        self.staging = staging
        self.managed = managed
        self.directories = directories

        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        var folder = managed
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    public func publish(_ staged: StagedFile, for task: DownloadTask) async throws -> PublishedFile
    {
        guard staged.taskID == task.id, staged.attemptID == task.attemptID else {
            throw DownloadFileError.unsafePath
        }
        let source = try confinedFile(staged.relativePath, under: staging)

        // Resource-access errors can be transient (for example file protection while locked).
        // Preserve their cause and staging; only a successful negative probe rejects the bytes.
        guard try await isPlayable(source) else { throw DownloadFileError.invalidMedia }

        let lease = try await directory(task.destination)
        // The source survives until the guarded completed-state commit. A crash between rename
        // and commit can recover the exact file by its attempt name and content identity.
        return try withExtendedLifetime(lease) {
            try publishBytes(source: source, directory: lease.url, task: task)
        }
    }

    private func publishBytes(source: URL, directory: URL, task: DownloadTask) throws
        -> PublishedFile
    {
        let manager = FileManager.default
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { throw DownloadFileError.emptyFile }

        let base = URL(fileURLWithPath: task.filename).deletingPathExtension().lastPathComponent
        let legacyTitle = String(base.prefix(Self.legacyTitleLimit))
        let suffix = task.id.uuidString + "-" + task.attemptID.uuidString
        var index = 0

        while true {
            let tail = index == 0 ? "" : "-\(index)"
            let ending = "-\(suffix)\(tail).mp4"
            let name = fittingFilename(title: legacyTitle, ending: ending)

            // A previous app version may have already renamed a valid, wider Unicode component.
            let legacyName = legacyTitle + ending
            if legacyName != name {
                let legacyURL = try confinedFile(legacyName, under: directory)
                if manager.fileExists(atPath: legacyURL.path),
                    try digest(legacyURL) == digest(source)
                {
                    return try publishedFile(
                        at: legacyURL, size: size, destination: task.destination)
                }
            }

            let destination = try confinedFile(name, under: directory)
            if manager.fileExists(atPath: destination.path) {
                if try digest(destination) == digest(source) {
                    return try publishedFile(
                        at: destination, size: size, destination: task.destination)
                }
                index += 1
                continue
            }

            let temporary = directory.appending(
                path: ".sctv-\(task.id.uuidString)-\(task.attemptID.uuidString).part")
            // A previous process may have died mid-copy. This identity is exclusively owned
            // by the same task/attempt, so retry can safely remove only its partial output.
            if manager.fileExists(atPath: temporary.path) {
                try manager.removeItem(at: temporary)
            }
            defer { try? manager.removeItem(at: temporary) }
            try copyFile(source, temporary)

            // FileManager.moveItem refuses to replace an existing destination, including races.
            do {
                try manager.moveItem(at: temporary, to: destination)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                index += 1
                continue
            }
            return try publishedFile(at: destination, size: size, destination: task.destination)
        }
    }

    private func fittingFilename(title: String, ending: String) -> String {
        var position = title.startIndex
        var utf8Budget = Self.filenameComponentLimit - ending.utf8.count
        var utf16Budget = Self.filenameComponentLimit - ending.utf16.count

        // External volumes may count bytes while APFS counts UTF-16 units.
        // Advance by complete graphemes so both stores receive a valid component.
        while position < title.endIndex {
            let end = title.index(after: position)
            let grapheme = title[position..<end].decomposedStringWithCanonicalMapping
            utf8Budget -= grapheme.utf8.count
            utf16Budget -= grapheme.utf16.count
            guard utf8Budget >= 0, utf16Budget >= 0 else { break }
            position = end
        }

        let shortenedTitle = String(title[..<position])
        return (shortenedTitle.isEmpty ? "download" : shortenedTitle) + ending
    }

    private func publishedFile(
        at url: URL, size: Int, destination: FileDestination
    ) throws -> PublishedFile {
        PublishedFile(
            destination: destination, relativeFilename: url.lastPathComponent,
            byteSize: Int64(size), fileIdentity: try identity(url))
    }

    public func cleanup(_ staged: StagedFile) async throws {
        let source = try confinedFile(staged.relativePath, under: staging)
        if FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.removeItem(at: source)
        }
    }

    public func delete(_ file: PublishedFile) async throws {
        let lease = try await open(file)
        try withExtendedLifetime(lease) { try FileManager.default.removeItem(at: lease.url) }
    }

    public func exists(_ file: PublishedFile) async throws -> Bool {
        do {
            _ = try await open(file)
            return true
        } catch DownloadFileError.missingFile, DownloadFileError.identityChanged {
            return false
        }
    }

    public func open(_ file: PublishedFile) async throws -> LocalFileLease {
        let directoryLease = try await directory(file.destination)
        let url = try confinedFile(file.relativeFilename, under: directoryLease.url)

        // Only report a missing file while the destination itself is still accessible.
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            guard try identity(url) == file.fileIdentity else {
                throw DownloadFileError.identityChanged
            }
        } catch  where Self.isFileNotFound(error) {
            let directory = try directoryLease.url.resourceValues(forKeys: [.isDirectoryKey])
            guard directory.isDirectory == true else { throw DownloadFileError.accessDenied }
            throw DownloadFileError.missingFile
        }

        // The file lease keeps its directory scope active for the caller's operation.
        return try LocalFileLease(url: url) { _ = directoryLease }
    }

    private static func isFileNotFound(_ error: any Error) -> Bool {
        if let cocoa = error as? CocoaError {
            return cocoa.code == .fileNoSuchFile || cocoa.code == .fileReadNoSuchFile
        }
        return (error as? POSIXError)?.code == .ENOENT
    }

    private func directory(_ destination: FileDestination) async throws -> LocalFileLease {
        switch destination {
        case .applicationManaged: try LocalFileLease(url: managed) {}
        case .external(let id): try await directories.open(id)
        }
    }

    private func identity(_ url: URL) throws -> String {
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let inode = values[.systemFileNumber] as? NSNumber,
            let size = values[.size] as? NSNumber, let modified = values[.modificationDate] as? Date
        else { throw DownloadFileError.missingFile }
        return "\(inode)-\(size)-\(modified.timeIntervalSince1970)"
    }

    private func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: Self.digestChunkSize), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
