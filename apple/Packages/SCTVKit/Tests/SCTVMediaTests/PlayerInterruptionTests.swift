@preconcurrency import AVFoundation
import Foundation
import SCTVCore
import Testing

@testable import SCTVMedia

@MainActor
struct PlayerInterruptionTests {
    struct SlowTransport: MediaRangeTransport {
        let base: FixtureFileTransport

        func read(source: MediaSource, range: ByteRange) async throws -> RangeResponse {
            if source.quality == .smooth { try await Task.sleep(for: .milliseconds(50)) }
            return try await base.read(source: source, range: range)
        }
    }

    actor TrackingTransport: MediaRangeTransport {
        let base: FixtureFileTransport
        var active = 0

        init(base: FixtureFileTransport) { self.base = base }

        func read(source: MediaSource, range: ByteRange) async throws -> RangeResponse {
            active += 1
            defer { active -= 1 }
            try await Task.sleep(for: .seconds(10))
            return try await base.read(source: source, range: range)
        }
    }

    @Test(.timeLimit(.minutes(1))) func cancelledOpenCancelsOwnedReads() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "probe", withExtension: "mp4", subdirectory: "Fixtures"))
        let transport = TrackingTransport(base: FixtureFileTransport(url: url))
        let coordinator = PlaybackCoordinator(transport: transport)
        let content = try ContentRef(programmeID: "1", dateID: "2", contentID: "3")
        let source = try MediaSource(
            url: URL(string: "https://fscgc.scgchc.com/test.mp4")!,
            quality: .standard)
        let task = Task {
            try await coordinator.open(
                PlaybackRequest(
                    content: content, title: "Fixture", sources: [source], quality: .standard))
        }
        for _ in 0..<100 where await transport.active == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await transport.active > 0)
        task.cancel()
        _ = await task.result
        try await Task.sleep(for: .milliseconds(100))
        #expect(await transport.active == 0)
        #expect(coordinator.player.currentItem == nil)
        coordinator.beginDismissal()
        await coordinator.finishDismissal()
    }

    private func setup() async throws -> PlaybackCoordinator {
        let url = try #require(
            Bundle.module.url(forResource: "probe", withExtension: "mp4", subdirectory: "Fixtures"))
        let coordinator = PlaybackCoordinator(
            transport: SlowTransport(base: FixtureFileTransport(url: url)))
        let content = try ContentRef(programmeID: "1", dateID: "2", contentID: "3")
        let sources = try [VideoQuality.standard, .smooth].map {
            try MediaSource(
                url: URL(
                    string: "https://fscgc.scgchc.com/\($0.rawValue).mp4")!,
                quality: $0)
        }
        _ = try await coordinator.open(
            PlaybackRequest(
                content: content, title: "Fixture", sources: sources, quality: .standard,
                resumeMilliseconds: 1000))
        return coordinator
    }

    @Test(.timeLimit(.minutes(1))) func pauseDuringReplacement() async throws {
        let coordinator = try await setup()
        coordinator.setPlaybackIntent(.playing)
        let task = Task { try await coordinator.switchQuality(.smooth) }
        for _ in 0..<100 where coordinator.state != .preparing {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.state == .preparing)
        coordinator.setPlaybackIntent(.paused)
        try await task.value
        #expect(coordinator.player.rate == 0)
        #expect(coordinator.capture()?.playIntent == .paused)
        coordinator.beginDismissal()
        await coordinator.finishDismissal()
    }

    @Test(.timeLimit(.minutes(1))) func abortedSeekKeepsServiceUsable() async throws {
        let coordinator = try await setup()
        let task = Task { try await coordinator.seek(to: 8000) }
        await Task.yield()
        coordinator.player.currentItem?.cancelPendingSeeks()
        _ = await task.result
        coordinator.setPlaybackIntent(.playing)
        #expect(coordinator.player.rate > 0)
        coordinator.beginDismissal()
        await coordinator.finishDismissal()
    }
}
