import Foundation
import SCTVCore
import Testing

struct HistoryDayTests {
    @Test func groupsByLocalViewingDayInsteadOfBroadcastDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let midnight = ISO8601DateFormatter().date(from: "2026-10-22T16:00:00Z")!
        let first = HistoryEntry(
            content: try ContentRef(programmeID: "1", dateID: "2", contentID: "3"),
            programmeName: "News", broadcastDate: "2025-01-01", title: "First", cover: nil,
            positionMs: 1000, durationMs: nil, updatedAt: midnight.addingTimeInterval(-1),
            completed: false)
        let second = HistoryEntry(
            content: try ContentRef(programmeID: "1", dateID: "2", contentID: "4"),
            programmeName: "News", broadcastDate: "2025-01-01", title: "Second", cover: nil,
            positionMs: 1000, durationMs: nil, updatedAt: midnight, completed: false)
        let groups = HistoryDay.group([first, second], calendar: calendar)
        #expect(groups.count == 2)
        #expect(groups.first?.entries.first?.title == "Second")
    }
}
