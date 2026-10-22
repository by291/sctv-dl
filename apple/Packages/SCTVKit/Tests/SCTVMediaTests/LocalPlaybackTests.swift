import Foundation
import SCTVCore
import Testing

@testable import SCTVMedia

@MainActor
struct LocalPlaybackTests {
    actor RejectNetwork: MediaRangeTransport {
        var count = 0
        func read(source: MediaSource, range: ByteRange) async throws -> RangeResponse {
            count += 1
            throw URLError(.notConnectedToInternet)
        }
    }

    @Test func opensLocalFileWithoutNetwork() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "probe", withExtension: "mp4", subdirectory: "Fixtures"))
        let transport = RejectNetwork()
        let player = PlaybackCoordinator(transport: transport)
        let content = try ContentRef(programmeID: "1", dateID: "2", contentID: "3")
        _ = try await player.open(
            PlaybackRequest(
                content: content, title: "Local", sources: [], quality: .standard,
                resumeMilliseconds: 3000, localFile: LocalFileLease(url: url)))
        #expect(abs((player.capture()?.positionMs ?? 0) - 3000) < 100)
        #expect(await transport.count == 0)
        player.beginDismissal()
        await player.finishDismissal()
    }

    @Test func missingLocalFileDoesNotFallBackOnline() async throws {
        let transport = RejectNetwork()
        let player = PlaybackCoordinator(transport: transport)
        let content = try ContentRef(programmeID: "1", dateID: "2", contentID: "3")
        let source = try MediaSource(
            url: URL(string: "https://fscgc.scgchc.com/probe.mp4")!, quality: .standard,
            productVersion: "test")
        await #expect(throws: (any Error).self) {
            try await player.open(
                PlaybackRequest(
                    content: content, title: "Missing", sources: [source], quality: .standard,
                    localFile: LocalFileLease(
                        url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
                            UUID().uuidString))))
        }
        #expect(await transport.count == 0)
        player.beginDismissal()
        await player.finishDismissal()
    }
}
