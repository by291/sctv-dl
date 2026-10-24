import Foundation
import Observation
import SCTVCore

@MainActor @Observable
final class ArchiveDateBrowserModel {
    let months: [ArchiveDateGroup]
    private let searchKeys: [String: String]
    private(set) var monthID: String
    private(set) var visibleMonths: [ArchiveDateGroup] = []
    var search = "" {
        didSet { rebuildVisibleMonths() }
    }

    var searching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var monthIndex: Int { months.firstIndex { $0.id == monthID } ?? 0 }
    var monthTitle: String { months.first { $0.id == monthID }?.title ?? "全部日期" }
    var hasPreviousMonth: Bool { monthIndex + 1 < months.count }
    var hasNextMonth: Bool { monthIndex > 0 }

    init(dates: [BroadcastDate], selectedID: String?) {
        months = ArchiveDateGroup.group(dates, query: "")
        searchKeys = Dictionary(
            dates.map { ($0.id, $0.date.replacingOccurrences(of: "-", with: "")) },
            uniquingKeysWith: { first, _ in first })
        monthID =
            months.first { $0.dates.contains { $0.id == selectedID } }?.id
            ?? months.first?.id ?? ""
        rebuildVisibleMonths()
    }

    func selectMonth(_ id: String) {
        guard months.contains(where: { $0.id == id }) else { return }
        monthID = id
        search = ""
    }

    func changeMonth(by delta: Int) {
        let index = monthIndex + delta
        guard months.indices.contains(index) else { return }
        selectMonth(months[index].id)
    }

    private func rebuildVisibleMonths() {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
        guard !query.isEmpty else {
            visibleMonths = months.filter { $0.id == monthID }
            return
        }
        // Group and normalize once per presentation, rather than sorting thousands
        // of dates on every body evaluation or search-field focus change.
        visibleMonths = months.compactMap { month in
            let dates = month.dates.filter { searchKeys[$0.id]?.contains(query) == true }
            return dates.isEmpty
                ? nil : ArchiveDateGroup(id: month.id, title: month.title, dates: dates)
        }
    }
}
