import Foundation
import Testing

@testable import SCTVCore

struct ProgrammeRulesTests {
    @Test func matchesOnlyExactProgrammeAndBroadcastDate() {
        #expect(
            ProgrammeRules.isFullEpisode(
                title: " 栏目 （ 2026.10.06 ） ", programmeName: "栏目", broadcastDate: "2026-10-06"))
        #expect(
            !ProgrammeRules.isFullEpisode(
                title: "栏目（2026.10.06）片段", programmeName: "栏目", broadcastDate: "2026-10-06"))
    }

    @Test func sortsOffsetFreePublicationInShanghaiAndLeavesUnknownLast() {
        let rows = [
            ProgrammeContent(
                id: "1", title: "A", cover: nil, video: nil, smoothVideo: nil,
                publishedAt: "2026-10-09 18:40:05"),
            ProgrammeContent(
                id: "2", title: "B", cover: nil, video: nil, smoothVideo: nil,
                publishedAt: "2026-10-09T10:30:00Z"),
            ProgrammeContent(
                id: "3", title: "C", cover: nil, video: nil, smoothVideo: nil, publishedAt: nil),
        ]
        #expect(ProgrammeRules.sortClips(rows, ascending: true).map(\.id) == ["2", "1", "3"])
        #expect(ProgrammeRules.sortClips(rows, ascending: false).map(\.id) == ["1", "2", "3"])
    }

    @Test func trimsPublicationTextBeforeParsing() {
        #expect(
            ProgrammeRules.publicationTime(" 2026-10-09 18:40:05 ")
                == ProgrammeRules.publicationTime("2026-10-09 18:40:05"))
    }
}
