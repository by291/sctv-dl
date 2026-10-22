import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: ContentRef { content }
    public let content: ContentRef
    public let programmeName: String
    public let broadcastDate: String
    public let title: String
    public let cover: URL?
    public let positionMs: Int64
    public let durationMs: Int64?
    public let updatedAt: Date
    public let completed: Bool

    public init(
        content: ContentRef, programmeName: String, broadcastDate: String, title: String,
        cover: URL?, positionMs: Int64, durationMs: Int64?, updatedAt: Date, completed: Bool
    ) {
        self.content = content
        self.programmeName = programmeName
        self.broadcastDate = broadcastDate
        self.title = title
        self.cover = cover
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.updatedAt = updatedAt
        self.completed = completed
    }
}

public enum HistoryRules {
    public static func isCompleted(positionMs: Int64, durationMs: Int64?, ended: Bool) -> Bool {
        if ended { return true }
        guard let durationMs, durationMs > 0 else { return false }
        return Double(positionMs) / Double(durationMs) >= 0.95
    }

    public static func resumePosition(positionMs: Int64, completed: Bool) -> Int64 {
        completed ? 0 : max(0, positionMs)
    }
}
