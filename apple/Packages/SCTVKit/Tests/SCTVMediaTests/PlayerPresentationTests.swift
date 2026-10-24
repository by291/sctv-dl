import Foundation
import SCTVCore
import Testing

@testable import SCTVMedia

@MainActor struct PlayerPresentationTests {
    private actor DelayedHistory: HistoryRepository {
        var pending: CheckedContinuation<HistorySession, any Error>?
        func begin(_ request: PlaybackRequest) async throws -> HistorySession {
            if request.title == "first" {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return HistorySession(id: UUID(), previous: nil)
        }
        func failFirst() {
            pending?.resume(throwing: CocoaError(.fileReadNoPermission))
            pending = nil
        }
        func record(_ sample: PlaybackSnapshot, session: UUID, sequence: UInt64) async throws {}
        func remove(_ content: ContentRef) async throws {}
        func clear() async throws {}
        func entries() async throws -> [HistoryEntry] { [] }
        func updates() async -> AsyncStream<[HistoryEntry]> { AsyncStream { $0.finish() } }
    }

    @Test func oldHistoryFailureCannotReplaceNewPresentationWarning() async throws {
        let history = DelayedHistory()
        let session = PlayerSession(history: history)
        let first = try #require(
            session.beginPresentation(forRequest: session.reservePlaybackRequest()))
        let firstRequest = try request("first")
        let opening = Task { await session.open(firstRequest, forPresentation: first) }
        for _ in 0..<100 {
            if await history.pending != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await history.pending != nil)
        let second = try #require(
            session.beginPresentation(forRequest: session.reservePlaybackRequest()))
        await session.open(try request("second"), forPresentation: second)

        await history.failFirst()
        await opening.value
        #expect(session.warning == nil)
        #expect(session.title == "second")
        await session.close(presentationID: second)
    }

    @Test func slowEarlierRequestCannotReplaceNewerPlayback() async throws {
        let session = PlayerSession(history: PlaybackHistoryTests.Repository())
        let slow = session.reservePlaybackRequest()
        let newest = session.reservePlaybackRequest()
        let token = try #require(session.beginPresentation(forRequest: newest))
        await session.open(try request("newest"), forPresentation: token)
        #expect(session.playback.state == .ready)

        // The older resolver finishes only after the newer player has become ready.
        #expect(session.beginPresentation(forRequest: slow) == nil)
        #expect(session.title == "newest")
        await session.close(presentationID: token)
    }

    @Test func oldDismissalCannotCloseReplacementAndCloseInvalidatesPendingResolution() async throws
    {
        let session = PlayerSession(history: PlaybackHistoryTests.Repository())
        let first = try #require(
            session.beginPresentation(forRequest: session.reservePlaybackRequest()))
        await session.open(try request("first"), forPresentation: first)
        let second = try #require(
            session.beginPresentation(forRequest: session.reservePlaybackRequest()))
        await session.open(try request("second"), forPresentation: second)

        await session.close(presentationID: first)
        #expect(session.playback.state == .ready)
        #expect(session.title == "second")
        let pending = session.reservePlaybackRequest()
        await session.close(presentationID: second)
        #expect(session.beginPresentation(forRequest: pending) == nil)
        #expect(session.playback.state == .idle)
    }

    private func request(_ id: String) throws -> PlaybackRequest {
        let url = try #require(
            Bundle.module.url(forResource: "probe", withExtension: "mp4", subdirectory: "Fixtures"))
        return PlaybackRequest(
            content: try ContentRef(
                programmeID: "1", dateID: "2", contentID: id == "first" ? "3" : "4"),
            title: id, sources: [], quality: .standard, localFile: try LocalFileLease(url: url))
    }

    @Test func discardedSceneReleasesItsPlayerButCannotCloseAnotherScenesReplacement() async throws
    {
        let session = PlayerSession(history: PlaybackHistoryTests.Repository())
        var owner: PlayerPresentationLifetime? = PlayerPresentationLifetime(session: session)
        let first = try #require(
            session.beginPresentation(forRequest: session.reservePlaybackRequest()))
        owner?.takeOwnership(of: first)
        await session.open(try request("first"), forPresentation: first)

        owner = nil
        for _ in 0..<100 where session.playback.state != .idle {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(session.playback.state == .idle)
        #expect(session.playback.player.currentItem == nil)

        owner = PlayerPresentationLifetime(session: session)
        let second = try #require(
            session.beginPresentation(forRequest: session.reservePlaybackRequest()))
        owner?.takeOwnership(of: second)
        await session.open(try request("second"), forPresentation: second)
        let replacement = try #require(
            session.beginPresentation(forRequest: session.reservePlaybackRequest()))
        await session.open(try request("replacement"), forPresentation: replacement)

        owner = nil
        // Await the old token's close as well as the queued deinitialization work.
        await session.close(presentationID: second)
        await Task.yield()
        #expect(session.playback.state == .ready)
        #expect(session.title == "replacement")
        await session.close(presentationID: replacement)
    }
}
