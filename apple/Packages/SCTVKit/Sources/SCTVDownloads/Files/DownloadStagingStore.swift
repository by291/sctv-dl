import Foundation
import SCTVCore

public enum StagingError: LocalizedError, Sendable {
    case missingCallbackFile
    case stagedPathOccupied

    public var errorDescription: String? {
        switch self {
        case .missingCallbackFile: "临时下载文件已失效，请重试。"
        case .stagedPathOccupied: "暂存文件路径不可用，请重试。"
        }
    }
}

/// Synchronous file ownership transfer for URLSession's temporary callback lifetime.
public final class DownloadStagingStore: Sendable {
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    public func adoptTemporaryFile(at temporary: URL, taskID: UUID, attemptID: UUID) throws
        -> StagedFile
    {
        let staged = reference(taskID: taskID, attemptID: attemptID)
        let destination = root.appending(path: staged.relativePath)
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            guard try destination.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else { throw StagingError.stagedPathOccupied }
            return staged
        }
        guard manager.fileExists(atPath: temporary.path) else {
            throw StagingError.missingCallbackFile
        }

        // A same-volume rename avoids duplicating a large download and is immediately
        // discoverable after relaunch. Cross-volume callbacks fall back to a private part file.
        if (try? manager.moveItem(at: temporary, to: destination)) != nil {
            return staged
        }
        if manager.fileExists(atPath: destination.path) {
            guard try destination.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else { throw StagingError.stagedPathOccupied }
            return staged
        }

        let part = folder.appending(path: ".\(UUID().uuidString).part")
        defer { try? manager.removeItem(at: part) }
        try manager.copyItem(at: temporary, to: part)
        try manager.moveItem(at: part, to: destination)
        return staged
    }

    public func stagedFile(taskID: UUID, attemptID: UUID) throws -> StagedFile? {
        let staged = reference(taskID: taskID, attemptID: attemptID)
        let destination = root.appending(path: staged.relativePath)
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }
        guard try destination.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        else { throw StagingError.stagedPathOccupied }
        return staged
    }

    public func stagedFiles() throws -> [StagedFile] {
        let manager = FileManager.default
        let folders = try manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])
        var result: [StagedFile] = []
        for folder in folders {
            guard let taskID = UUID(uuidString: folder.lastPathComponent),
                try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            else { continue }
            let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "mp4" {
                guard
                    let attemptID = UUID(
                        uuidString: file.deletingPathExtension().lastPathComponent),
                    let staged = try stagedFile(taskID: taskID, attemptID: attemptID)
                else { continue }
                result.append(staged)
            }
        }
        return result
    }

    private func reference(taskID: UUID, attemptID: UUID) -> StagedFile {
        StagedFile(
            taskID: taskID, attemptID: attemptID,
            relativePath: "\(taskID.uuidString)/\(attemptID.uuidString).mp4")
    }
}
