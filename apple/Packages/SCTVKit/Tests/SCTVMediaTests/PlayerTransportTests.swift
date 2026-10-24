@preconcurrency import AVFoundation
import Foundation
import SCTVCore
import Testing

@testable import SCTVMedia

@MainActor
struct PlayerTransportTests {
    @Test(.timeLimit(.minutes(1))) func playsAndSeeksThroughHTTPRangeTransport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VideoURLProtocol.self]
        let coordinator = PlaybackCoordinator(
            transport: URLSessionRangeTransport(configuration: configuration))
        let source = try MediaSource(
            url: URL(string: "https://fscgc.scgchc.com/probe.mp4")!, quality: .standard)
        let content = try ContentRef(programmeID: "1", dateID: "2", contentID: "3")

        _ = try await coordinator.open(
            PlaybackRequest(
                content: content, title: "Fixture", sources: [source], quality: .standard))
        #expect(coordinator.player.rate == 0)
        coordinator.setPlaybackIntent(.playing)
        for _ in 0..<100 where (coordinator.capture()?.positionMs ?? 0) < 200 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect((coordinator.capture()?.positionMs ?? 0) >= 200)
        coordinator.setPlaybackIntent(.paused)

        for position: Int64 in [8000, 1000, 11000] {
            try await coordinator.seek(to: position)
            let snapshot = try #require(coordinator.capture())
            #expect(abs(snapshot.positionMs - position) < 100)
        }
        try await coordinator.retry()
        #expect(coordinator.capture()?.playIntent == .paused)
        #expect(abs((coordinator.capture()?.positionMs ?? 0) - 11000) < 100)

        coordinator.beginDismissal()
        await coordinator.finishDismissal()
        #expect(coordinator.player.currentItem == nil)
    }
}

/// Exercises URLSession and AVFoundation together while replacing only the remote HTTP server.
private final class VideoURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try #require(
                Bundle.module.url(
                    forResource: "probe", withExtension: "mp4", subdirectory: "Fixtures"))
            let input = try #require(request.value(forHTTPHeaderField: "Range"))
            let bounds = input.dropFirst(6).split(separator: "-")
            #expect(input.hasPrefix("bytes="))
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://scgc.video.play/")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "okhttp/4.12.0")
            #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
            let start = try #require(UInt64(bounds.first ?? ""))
            let requestedEnd = try #require(UInt64(bounds.last ?? ""))
            #expect(requestedEnd >= start && requestedEnd - start < 256 * 1024)

            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let total = try file.seekToEnd()
            guard start < total, requestedEnd >= start else {
                throw MediaTransportError.invalidRange
            }
            let end = min(requestedEnd, total - 1)
            try file.seek(toOffset: start)
            let bytes = try file.read(upToCount: Int(end - start + 1))
            let data = try #require(bytes)
            let response = try #require(
                HTTPURLResponse(
                    url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": "video/mp4", "Content-Length": String(data.count),
                        "Content-Range": "bytes \(start)-\(end)/\(total)",
                    ]))

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
