@preconcurrency import AVFoundation
import Foundation
import SCTVCore
import Testing

@testable import SCTVMedia

@MainActor
struct PlayerSessionTests {
    private func request(resume: Int64 = 3000) throws -> PlaybackRequest {
        let content = try ContentRef(programmeID: "1", dateID: "2", contentID: "3")
        let standard = try MediaSource(
            url: URL(string: "https://fscgc.scgchc.com/probe.mp4")!, quality: .standard,
            productVersion: "test")
        let smooth = try MediaSource(
            url: URL(string: "https://fscgc.scgchc.com/smooth.mp4")!, quality: .smooth,
            productVersion: "test")
        return PlaybackRequest(
            content: content, title: "测试视频", sources: [standard, smooth], quality: .standard,
            resumeMilliseconds: resume)
    }

    private func coordinator() throws -> PlaybackCoordinator {
        let url = try #require(
            Bundle.module.url(forResource: "probe", withExtension: "mp4", subdirectory: "Fixtures"))
        return PlaybackCoordinator(transport: FixtureFileTransport(url: url))
    }

    @Test(.timeLimit(.minutes(1))) func repeatedDismissalReleasesPlayerItems() async throws {
        let coordinator = try coordinator()
        for _ in 0..<5 {
            _ = try await coordinator.open(request())
            weak var item = coordinator.player.currentItem
            #expect(item != nil)
            coordinator.beginDismissal()
            await coordinator.finishDismissal()
            for _ in 0..<100 where item != nil { try await Task.sleep(for: .milliseconds(10)) }
            #expect(item == nil)
            #expect(coordinator.state == .idle)
        }
    }

    @Test(.timeLimit(.minutes(1))) func opensPausedAndRestoresAfterSeek() async throws {
        let coordinator = try coordinator()
        _ = try await coordinator.open(request())
        let snapshot = try #require(coordinator.capture())
        #expect(snapshot.playIntent == .paused)
        #expect(abs(snapshot.positionMs - 3000) < 100)
        #expect(snapshot.durationMs != nil)
        #expect(coordinator.player.rate == 0)
        coordinator.beginDismissal()
        await coordinator.finishDismissal()
        #expect(coordinator.capture() == nil)
        #expect(coordinator.player.currentItem == nil)
    }

    @Test(.timeLimit(.minutes(1))) func closeRevokesQualityResume() async throws {
        let coordinator = try coordinator()
        _ = try await coordinator.open(request())
        coordinator.setPlaybackIntent(.playing)
        let replacement = Task { try await coordinator.switchQuality(.smooth) }
        await Task.yield()
        coordinator.beginDismissal()
        _ = await replacement.result
        #expect(coordinator.player.rate == 0)
        #expect(coordinator.capture()?.playIntent == .paused)
        await coordinator.finishDismissal()
    }

    @Test(.timeLimit(.minutes(1))) func pipRetainsSessionUntilFinished() async throws {
        let coordinator = try coordinator()
        let id = try await coordinator.open(request())
        coordinator.setPictureInPictureActive(true)
        coordinator.beginDismissal()
        await coordinator.finishDismissal()
        #expect(coordinator.capture()?.sessionID == id)
        coordinator.setPictureInPictureActive(false)
        await coordinator.finishDismissal()
        #expect(coordinator.capture() == nil)
    }

    @Test(.timeLimit(.minutes(1))) func nativeControlsUpdatePlayIntent() async throws {
        let coordinator = try coordinator()
        _ = try await coordinator.open(request())
        coordinator.player.playImmediately(atRate: 1.5)
        for _ in 0..<100 where coordinator.capture()?.playIntent != .playing {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.capture()?.playIntent == .playing)
        #expect(coordinator.capture()?.speed == 1.5)
        coordinator.beginDismissal()
        await coordinator.finishDismissal()
    }

    @Test(.timeLimit(.minutes(1))) func backgroundPreservesPipButRevokesOrdinaryPlayback()
        async throws
    {
        let coordinator = try coordinator()
        _ = try await coordinator.open(request())
        coordinator.setPlaybackIntent(.playing)
        coordinator.setPictureInPictureActive(true)
        coordinator.pauseForBackground()
        #expect(coordinator.player.rate > 0)
        coordinator.setPictureInPictureActive(false)
        coordinator.pauseForBackground()
        #expect(coordinator.player.rate == 0)
        coordinator.beginDismissal()
        await coordinator.finishDismissal()
    }
}
