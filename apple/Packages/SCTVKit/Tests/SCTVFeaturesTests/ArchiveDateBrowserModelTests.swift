import SCTVCore
import Testing

@testable import SCTVFeatures

@MainActor
struct ArchiveDateBrowserModelTests {
    private let dates = [
        BroadcastDate(id: "latest", date: "2026-10-23"),
        BroadcastDate(id: "same-month", date: "2026-10-22"),
        BroadcastDate(id: "previous", date: "2026-09-30"),
        BroadcastDate(id: "old", date: "2017-06-30"),
    ]

    @Test func opensAtSelectedMonthAndSearchesAcrossAllMonths() {
        let model = ArchiveDateBrowserModel(dates: dates, selectedID: "old")
        #expect(model.visibleMonths.flatMap(\.dates).map(\.id) == ["old"])
        model.search = "202610"
        #expect(model.visibleMonths.flatMap(\.dates).map(\.id) == ["latest", "same-month"])
        model.search = " 2026-09 "
        #expect(model.visibleMonths.flatMap(\.dates).map(\.id) == ["previous"])
        model.search = ""
        #expect(model.visibleMonths.flatMap(\.dates).map(\.id) == ["old"])
    }

    @Test func monthNavigationStaysWithinAvailableMonthsAndClearsSearch() {
        let model = ArchiveDateBrowserModel(dates: dates, selectedID: nil)
        model.changeMonth(by: -1)
        #expect(model.monthID == "2026-10")
        model.changeMonth(by: 1)
        #expect(model.monthID == "2026-09")
        model.search = "missing"
        #expect(model.visibleMonths.isEmpty)
        model.selectMonth("2017-06")
        #expect(model.search.isEmpty)
        #expect(model.visibleMonths.flatMap(\.dates).map(\.id) == ["old"])
        model.changeMonth(by: 1)
        #expect(model.monthID == "2017-06")
    }

    @Test func longArchiveOnlyPresentsOneMonthUntilSearching() {
        var dates: [BroadcastDate] = []
        for year in 2017...2026 {
            for month in 1...12 {
                for day in 1...28 {
                    let date =
                        "\(year)-\(month < 10 ? "0" : "")\(month)-\(day < 10 ? "0" : "")\(day)"
                    dates.append(BroadcastDate(id: date, date: date))
                }
            }
        }
        let model = ArchiveDateBrowserModel(dates: dates, selectedID: "2017-06-15")
        #expect(model.months.count == 120)
        #expect(model.visibleMonths.flatMap(\.dates).count == 28)
        #expect(model.monthID == "2017-06")
        model.search = "2017"
        #expect(model.visibleMonths.flatMap(\.dates).count == 336)
    }
}
