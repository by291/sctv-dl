import Foundation
import SCTVCore

struct ArchiveDateGroup: Identifiable {
    let id: String
    let title: String
    let dates: [BroadcastDate]

    static func group(_ dates: [BroadcastDate], query: String) -> [ArchiveDateGroup] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
        let filtered =
            query.isEmpty
            ? dates
            : dates.filter { $0.date.replacingOccurrences(of: "-", with: "").contains(query) }
        return Dictionary(grouping: filtered) { monthKey($0.date) }
            .map { key, dates in
                ArchiveDateGroup(
                    id: key, title: monthTitle(key),
                    dates: dates.sorted { $0.date > $1.date })
            }
            .sorted { $0.id > $1.id }
    }

    static func dateTitle(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard monthKey(date) != "", let month = Int(parts[1]), let day = Int(parts[2]) else {
            return date
        }
        return "\(month)月\(day)日"
    }

    private static func monthKey(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, Int(parts[0]) != nil,
            parts[1].count == 2, let month = Int(parts[1]), (1...12).contains(month),
            parts[2].count == 2, let day = Int(parts[2]), (1...31).contains(day)
        else { return "" }
        return "\(parts[0])-\(parts[1])"
    }

    private static func monthTitle(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return "其他日期" }
        return "\(parts[0])年\(month)月"
    }
}
