#if DEBUG
    import Foundation
    import SCTVCore

    actor FixtureProgrammeAPI: ProgrammeAPI {
        private var catalogueLoads = 0

        func catalogue() async throws -> [Programme] {
            catalogueLoads += 1
            let isRefresh = catalogueLoads > 1
            if ProcessInfo.processInfo.arguments.contains("--ui-slow-catalogue") {
                try await Task.sleep(for: .seconds(6))
            }
            let programmes = [
                Programme(id: "1", name: "四川新闻", cover: nil),
                Programme(
                    id: "2",
                    name: ProcessInfo.processInfo.arguments.contains("--ui-long-titles")
                        ? "防癌大讲堂" : "今日视点", cover: nil),
            ]
            if ProcessInfo.processInfo.arguments.contains("--ui-slow-catalogue"), isRefresh {
                return programmes + [Programme(id: "3", name: "刷新后的栏目", cover: nil)]
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-many-programmes") {
                return programmes
                    + (3...30).map { Programme(id: String($0), name: "栏目 \($0)", cover: nil) }
            }
            return programmes
        }
        func dates(programmeID: String) async throws -> [BroadcastDate] {
            if ProcessInfo.processInfo.arguments.contains("--ui-many-dates") {
                return Self.extendedDates
            }
            return [
                BroadcastDate(id: "20", date: "2026-10-22"),
                BroadcastDate(id: "19", date: "2026-10-21"),
            ]
        }
        func contents(programmeID: String, dateID: String) async throws -> [ProgrammeContent] {
            let date: String
            if ProcessInfo.processInfo.arguments.contains("--ui-many-dates") {
                date = (Self.extendedDates.first { $0.id == dateID }?.date ?? "2026-10-22")
                    .replacingOccurrences(of: "-", with: ".")
            } else {
                date = dateID == "20" ? "2026.10.22" : "2026.10.21"
            }
            var contents = [
                ProgrammeContent(
                    id: "30", title: "四川新闻（\(date)）", cover: nil,
                    video: URL(string: "https://fscgc.scgchc.com/probe.mp4"), smoothVideo: nil,
                    publishedAt: "2026-10-22 19:00:00"),
                ProgrammeContent(
                    id: "31",
                    title: ProcessInfo.processInfo.arguments.contains("--ui-long-content-titles")
                        ? "秋日里的城市故事" + String(repeating: "，记录城市发展和普通人的生活", count: 20)
                        : "秋日里的城市故事", cover: nil,
                    video: URL(string: "https://fscgc.scgchc.com/probe.mp4"), smoothVideo: nil,
                    publishedAt: "2026-10-22 19:05:00"),
            ]
            if ProcessInfo.processInfo.arguments.contains("--ui-long-content-titles") {
                contents.append(
                    ProgrammeContent(
                        id: "32", title: "城市一刻", cover: nil,
                        video: URL(string: "https://fscgc.scgchc.com/probe.mp4"), smoothVideo: nil,
                        publishedAt: "2026-10-22 19:06:00"))
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-many-contents") {
                contents += (32..<62).map { index in
                    ProgrammeContent(
                        id: String(index), title: "城市故事 第\(index)段", cover: nil,
                        video: URL(string: "https://fscgc.scgchc.com/probe.mp4"), smoothVideo: nil,
                        publishedAt: "2026-10-22 19:06:00")
                }
            }
            return contents
        }

        private static let extendedDates: [BroadcastDate] = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let latest = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return (0..<3402).map { offset in
                BroadcastDate(
                    id: String(20 + offset),
                    date: formatter.string(
                        from: latest.addingTimeInterval(-Double(offset) * 86_400)))
            }
        }()
    }
#endif
