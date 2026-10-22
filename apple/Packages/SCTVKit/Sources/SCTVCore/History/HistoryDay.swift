import Foundation

public struct HistoryDay: Identifiable, Sendable {
    public let id: Date
    public let entries: [HistoryEntry]

    public static func group(_ entries: [HistoryEntry], calendar: Calendar = .current)
        -> [HistoryDay]
    {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.updatedAt) }
            .map {
                HistoryDay(id: $0.key, entries: $0.value.sorted { $0.updatedAt > $1.updatedAt })
            }
            .sorted { $0.id > $1.id }
    }
}
