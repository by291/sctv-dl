import Foundation
import SCTVCore

/// A callback may finish before its native ID is committed. Keep the terminal receipt until
/// the coordinator has committed the matching attempt and native task result.
final class TerminalFailureStore: Sendable {
    private struct Receipt: Codable {
        let taskID: UUID
        let attemptID: UUID
        let nativeID: NativeTransferID
        let reason: String
        let resume: ResumeReference?
    }

    private let root: URL

    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    func save(_ event: TransferEvent) throws {
        guard case .failed(let taskID, let attemptID, let nativeID, let reason, let resume) = event
        else { return }
        let receipt = Receipt(
            taskID: taskID, attemptID: attemptID, nativeID: nativeID,
            reason: reason, resume: resume)
        let destination = path(taskID: taskID, attemptID: attemptID)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(receipt).write(to: destination, options: .atomic)
    }

    func event(taskID: UUID, attemptID: UUID) throws -> TransferEvent? {
        let destination = path(taskID: taskID, attemptID: attemptID)
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: destination))
        guard receipt.taskID == taskID, receipt.attemptID == attemptID else { return nil }
        return .failed(
            taskID: receipt.taskID, attemptID: receipt.attemptID,
            nativeID: receipt.nativeID, reason: receipt.reason, resume: receipt.resume)
    }

    func remove(taskID: UUID, attemptID: UUID) throws {
        let destination = path(taskID: taskID, attemptID: attemptID)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    private func path(taskID: UUID, attemptID: UUID) -> URL {
        root.appending(path: taskID.uuidString).appending(path: "\(attemptID.uuidString).json")
    }
}
