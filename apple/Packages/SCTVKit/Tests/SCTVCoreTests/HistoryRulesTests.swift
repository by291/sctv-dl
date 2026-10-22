import Foundation
import SCTVCore
import Testing

struct HistoryRulesTests {
    private struct Fixture: Decodable {
        struct Completion: Decodable {
            let positionMs: Int64
            let durationMs: Int64?
            let ended: Bool
            let completed: Bool
        }
        struct Resume: Decodable {
            let completed: Bool
            let positionMs: Int64
            let resumePosition: Int64
        }
        let completion: [Completion]
        let resume: [Resume]
    }

    @Test func matchesSharedHistoryFixtures() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "history", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        for sample in fixture.completion {
            #expect(
                HistoryRules.isCompleted(
                    positionMs: sample.positionMs, durationMs: sample.durationMs,
                    ended: sample.ended) == sample.completed)
        }
        for sample in fixture.resume {
            #expect(
                HistoryRules.resumePosition(
                    positionMs: sample.positionMs, completed: sample.completed)
                    == sample.resumePosition)
        }
    }
}
