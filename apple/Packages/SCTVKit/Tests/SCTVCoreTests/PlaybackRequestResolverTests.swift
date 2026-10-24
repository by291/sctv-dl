import Foundation
import SCTVCore
import Testing

struct PlaybackRequestResolverTests {
    private let programme = Programme(id: "1", name: "栏目", cover: nil)
    private let broadcast = BroadcastDate(id: "2", date: "2026-10-24")
    private let item = ProgrammeContent(
        id: "3", title: "最新节目标题", cover: URL(string: "https://example.com/cover.jpg"),
        video: URL(string: "https://fscgc.scgchc.com/standard.mp4"),
        smoothVideo: URL(string: "https://fscgc.scgchc.com/smooth.mp4"), publishedAt: nil)

    @Test func preparesSourcesWithUpstreamHeadersAndMatchingHistory() async throws {
        let unrelated = try entry(contentID: "4", position: 9_000)
        let saved = try entry(position: 42_000)
        let resolver = PlaybackRequestResolver(
            api: API(items: []), history: History(values: [unrelated, saved]))

        let request = try await resolver.prepare(
            item, programme: programme, broadcast: broadcast, quality: .smooth)

        #expect(request.content == saved.content)
        #expect(request.resumeMilliseconds == 42_000)
        #expect(request.quality == .smooth)
        #expect(request.sources.count == 2)
        #expect(request.sources.allSatisfy { $0.headers["User-Agent"] == "okhttp/4.12.0" })
        #expect(request.title == item.title)
        #expect(request.cover == item.cover)
        #expect(request.programmeName == programme.name)
        #expect(request.broadcastDate == broadcast.date)
    }

    @Test(arguments: [false, true])
    func resolvesSavedEntryWithFreshMetadataAndSavedResume(completed: Bool) async throws {
        let saved = try entry(position: 42_000, completed: completed)
        let newer = try entry(position: 70_000)
        let resolver = PlaybackRequestResolver(
            api: API(items: [item]), history: History(values: [newer]))

        let request = try await resolver.resolve(saved, quality: .standard)

        #expect(request.title == item.title)
        #expect(request.cover == item.cover)
        #expect(request.resumeMilliseconds == (completed ? 0 : 42_000))
        #expect(request.content == saved.content)
        #expect(request.programmeName == saved.programmeName)
        #expect(request.broadcastDate == saved.broadcastDate)
    }

    @Test func restartsCompletedHistoryAndHonorsExplicitResume() async throws {
        let saved = try entry(position: 99_000, completed: true)
        let resolver = PlaybackRequestResolver(
            api: API(items: []), history: History(values: [saved]))

        let restarted = try await resolver.prepare(
            item, programme: programme, broadcast: broadcast, quality: .standard)
        let overridden = try await resolver.prepare(
            item, programme: programme, broadcast: broadcast, quality: .standard,
            resumeOverride: 12_000)

        #expect(restarted.resumeMilliseconds == 0)
        #expect(overridden.resumeMilliseconds == 12_000)
    }

    @Test func historyFailureStillAllowsPlaybackAndQualityFallback() async throws {
        let smoothOnly = ProgrammeContent(
            id: item.id, title: item.title, cover: nil, video: nil,
            smoothVideo: item.smoothVideo, publishedAt: nil)
        let resolver = PlaybackRequestResolver(
            api: API(items: [smoothOnly]), history: History(fails: true))

        let request = try await resolver.prepare(
            smoothOnly, programme: programme, broadcast: broadcast, quality: .standard)
        let resumed = try await resolver.resolve(entry(position: 21_000), quality: .standard)

        #expect(request.resumeMilliseconds == 0)
        #expect(request.quality == .smooth)
        #expect(request.sources.count == 1)
        #expect(request.sources.first?.url == smoothOnly.smoothVideo)
        #expect(resumed.resumeMilliseconds == 21_000)
    }

    @Test func reportsRemovedContentAndPreservesAPIFailures() async throws {
        let saved = try entry()
        let missing = PlaybackRequestResolver(
            api: API(items: []), history: History())
        let unavailable = PlaybackRequestResolver(
            api: API(items: [], fails: true), history: History())

        await #expect(throws: PlaybackRequestResolver.PreparationError.removed) {
            try await missing.resolve(saved, quality: .standard)
        }
        await #expect(throws: Failure.offline) {
            try await unavailable.resolve(saved, quality: .standard)
        }
    }

    private func entry(
        contentID: String = "3", position: Int64 = 0, completed: Bool = false
    ) throws -> HistoryEntry {
        HistoryEntry(
            content: try ContentRef(programmeID: "1", dateID: "2", contentID: contentID),
            programmeName: programme.name, broadcastDate: broadcast.date, title: "旧节目标题",
            cover: nil, positionMs: position, durationMs: 100_000,
            updatedAt: Date(timeIntervalSince1970: 0), completed: completed)
    }

    private enum Failure: Error, Equatable { case offline, history, unexpectedCall }

    private struct API: ProgrammeAPI {
        let items: [ProgrammeContent]
        var fails = false
        func catalogue() async throws -> [Programme] { throw Failure.unexpectedCall }
        func dates(programmeID: String) async throws -> [BroadcastDate] {
            throw Failure.unexpectedCall
        }
        func contents(programmeID: String, dateID: String) async throws -> [ProgrammeContent] {
            if fails { throw Failure.offline }
            return programmeID == "1" && dateID == "2" ? items : []
        }
    }

    private struct History: HistoryRepository {
        var values: [HistoryEntry] = []
        var fails = false
        func entries() async throws -> [HistoryEntry] {
            if fails { throw Failure.history }
            return values
        }
        func begin(_ request: PlaybackRequest) async throws -> HistorySession {
            throw Failure.unexpectedCall
        }
        func record(_ sample: PlaybackSnapshot, session: UUID, sequence: UInt64) async throws {
            throw Failure.unexpectedCall
        }
        func remove(_ content: ContentRef) async throws { throw Failure.unexpectedCall }
        func clear() async throws { throw Failure.unexpectedCall }
        func updates() async -> AsyncStream<[HistoryEntry]> { AsyncStream { $0.finish() } }
    }
}
