import Foundation
import SCTVCore

struct TransferCorrelation: Sendable {
    let taskID: UUID
    let attemptID: UUID

    init(_ task: DownloadTask) {
        taskID = task.id
        attemptID = task.attemptID
    }

    static func decode(_ description: String?) -> TransferCorrelation? {
        guard let description else { return nil }
        let parts = description.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, let taskID = UUID(uuidString: String(parts[0])),
            let attemptID = UUID(uuidString: String(parts[1]))
        else { return nil }
        return TransferCorrelation(taskID: taskID, attemptID: attemptID)
    }

    var taskDescription: String {
        "\(taskID.uuidString)|\(attemptID.uuidString)"
    }

    private init(taskID: UUID, attemptID: UUID) {
        self.taskID = taskID
        self.attemptID = attemptID
    }
}
