import SCTVCore
import Testing

@testable import SCTVFeatures

struct ArchiveDateGroupTests {
    @Test(arguments: ["2026", "202610", "20261023", "2026-10", "2026-10-23"])
    func searchesDatesWithOrWithoutHyphens(query: String) {
        let dates = [
            BroadcastDate(id: "match", date: "2026-10-23"),
            BroadcastDate(id: "other", date: "2025-09-22"),
        ]
        #expect(ArchiveDateGroup.group(dates, query: query).flatMap(\.dates).map(\.id) == ["match"])
    }

    @Test func groupsAvailableDatesByMonthWithoutLosingSelectionIDs() {
        let dates = [
            BroadcastDate(id: "old", date: "2025-12-31"),
            BroadcastDate(id: "first", date: "2026-10-02"),
            BroadcastDate(id: "last", date: "2026-10-23"),
        ]
        let groups = ArchiveDateGroup.group(dates, query: "")
        #expect(groups.map(\.id) == ["2026-10", "2025-12"])
        #expect(groups.first?.dates.map(\.id) == ["last", "first"])
        #expect(groups.first?.title == "2026年10月")
    }

    @Test func searchesAcrossYearsAndKeepsUnknownDateLabelsAvailable() {
        let dates = [
            BroadcastDate(id: "new", date: "2026-10-23"),
            BroadcastDate(id: "old", date: "2017-06-30"),
            BroadcastDate(id: "unknown", date: "特别节目"),
        ]
        #expect(
            ArchiveDateGroup.group(dates, query: " 2017-06 ").flatMap(\.dates).map(\.id) == ["old"])
        #expect(ArchiveDateGroup.group(dates, query: "1990").isEmpty)
        #expect(ArchiveDateGroup.group(dates, query: "").flatMap(\.dates).count == 3)
    }
}
