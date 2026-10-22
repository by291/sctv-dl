import Foundation
import SCTVCore

public enum ResumeDataError: Error, Sendable {
    case invalidReference
    case missingData
}

public final class ResumeDataStore: Sendable {
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    public func save(_ data: Data, taskID: UUID, attemptID: UUID) throws -> ResumeReference? {
        guard !data.isEmpty else { return nil }
        let name = "\(taskID.uuidString)/\(attemptID.uuidString).resume"
        let destination = root.appending(path: name)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return ResumeReference(relativePath: name)
    }

    public func load(_ reference: ResumeReference, taskID: UUID, attemptID: UUID) throws -> Data {
        let expected = "\(taskID.uuidString)/\(attemptID.uuidString).resume"
        guard reference.relativePath == expected else { throw ResumeDataError.invalidReference }
        let destination = root.appending(path: expected)
        guard let data = try? Data(contentsOf: destination), !data.isEmpty else {
            throw ResumeDataError.missingData
        }
        return data
    }

    public func remove(taskID: UUID, attemptID: UUID) throws {
        let destination = root.appending(path: taskID.uuidString)
            .appending(path: "\(attemptID.uuidString).resume")
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    public func prune(keepingAttempts: Set<UUID>) throws {
        let manager = FileManager.default
        let folders = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil {
            let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "resume" {
                guard
                    let attemptID = UUID(
                        uuidString: file.deletingPathExtension().lastPathComponent),
                    !keepingAttempts.contains(attemptID)
                else { continue }
                // A pause may be committing its just-written reference while reconciliation
                // runs. Explicit terminal cleanup is immediate; pruning waits out this race.
                let modified =
                    try file.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate ?? .now
                guard modified < Date.now.addingTimeInterval(-3600) else { continue }
                try manager.removeItem(at: file)
            }
            if try manager.contentsOfDirectory(atPath: folder.path).isEmpty {
                try manager.removeItem(at: folder)
            }
        }
    }
}
