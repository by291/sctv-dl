#if DEBUG
    import Foundation
    import SCTVCore

    struct FixtureProgrammeAPI: ProgrammeAPI {
        func catalogue() async throws -> [Programme] {
            [
                Programme(id: "1", name: "四川新闻", cover: nil),
                Programme(id: "2", name: "今日视点", cover: nil),
            ]
        }
        func dates(programmeID: String) async throws -> [BroadcastDate] {
            [
                BroadcastDate(id: "20", date: "2026-10-22"),
                BroadcastDate(id: "19", date: "2026-10-21"),
            ]
        }
        func contents(programmeID: String, dateID: String) async throws -> [ProgrammeContent] {
            let date = dateID == "20" ? "2026.10.22" : "2026.10.21"
            return [
                ProgrammeContent(
                    id: "30", title: "四川新闻（\(date)）", cover: nil,
                    video: URL(string: "https://fscgc.scgchc.com/probe.mp4"), smoothVideo: nil,
                    publishedAt: "2026-10-22 19:00:00"),
                ProgrammeContent(
                    id: "31", title: "秋日里的城市故事", cover: nil,
                    video: URL(string: "https://fscgc.scgchc.com/probe.mp4"), smoothVideo: nil,
                    publishedAt: "2026-10-22 19:05:00"),
            ]
        }
    }
#endif
