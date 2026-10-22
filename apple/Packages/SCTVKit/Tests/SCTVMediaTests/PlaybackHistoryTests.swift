import Foundation
import SCTVCore
import Testing

@testable import SCTVMedia

@MainActor
struct PlaybackHistoryTests {
    actor Repository: HistoryRepository {
        var samples: [PlaybackSnapshot] = []
        func begin(_ request: PlaybackRequest) async throws -> HistorySession {
            HistorySession(id: UUID(), previous: nil)
        }
        func record(_ sample: PlaybackSnapshot, session: UUID, sequence: UInt64) async throws {
            samples.append(sample)
        }
        func remove(_ content: ContentRef) async throws {}
        func clear() async throws {}
        func entries() async throws -> [HistoryEntry] { [] }
        func updates() async -> AsyncStream<[HistoryEntry]> { AsyncStream { $0.finish() } }
    }
    final class Clock { var time = 0.0 }

    @Test func throttlesProgressButFlushesPause() async throws {
        let repository = Repository()
        let clock = Clock()
        let recorder = PlaybackHistoryRecorder(repository: repository, now: { clock.time })
        let id = UUID()
        let content = try ContentRef(programmeID: "1", dateID: "2", contentID: "3")
        try await recorder.bind(
            request: PlaybackRequest(
                content: content, title: "Test", sources: [], quality: .standard),
            playbackSessionID: id)

        await recorder.consume(sample(id, 1000))
        clock.time = 4.999
        await recorder.consume(sample(id, 5999))
        #expect(await repository.samples.count == 1)
        clock.time = 5
        await recorder.consume(sample(id, 6000))
        #expect(await repository.samples.count == 2)
        await recorder.consume(sample(id, 6100, intent: .paused))
        #expect(await repository.samples.count == 3)
    }

    @Test func unsettledSeekDoesNotWriteZeroAndOldSessionIsIgnored() async throws {
        let repository = Repository()
        let recorder = PlaybackHistoryRecorder(repository: repository)
        let id = UUID()
        let content = try ContentRef(programmeID: "1", dateID: "2", contentID: "3")
        try await recorder.bind(
            request: PlaybackRequest(
                content: content, title: "Test", sources: [], quality: .standard),
            playbackSessionID: id)
        await recorder.consume(sample(id, 0, settled: false))
        await recorder.consume(sample(UUID(), 5000))
        #expect(await repository.samples.isEmpty)
    }

    private func sample(
        _ id: UUID, _ position: Int64, intent: PlaybackIntent = .playing, settled: Bool = true
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            sessionID: id, positionMs: position, durationMs: 10000, quality: .standard,
            speed: 1, playIntent: intent, settled: settled, ended: false)
    }
}
