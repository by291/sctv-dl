import Foundation
import SCTVCore
import Testing

@testable import SCTVMedia

struct RangeTransportTests {
    private func transport() -> URLSessionRangeTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        return URLSessionRangeTransport(configuration: configuration)
    }

    private func source(_ name: String) throws -> MediaSource {
        try MediaSource(
            url: URL(string: "https://fscgc.scgchc.com/\(name).mp4")!, quality: .standard,
            productVersion: "test")
    }

    @Test func acceptsMatchingRange() async throws {
        let response = try await transport().read(
            source: source("valid"), range: ByteRange(offset: 4096, length: 4))
        #expect(response.data == Data(repeating: 7, count: 4))
        #expect(response.contentLength == 10000)
    }

    @Test func rejectsWrongOffset() async throws {
        await #expect(throws: (any Error).self) {
            try await transport().read(
                source: source("wrong"), range: ByteRange(offset: 4096, length: 4))
        }
    }

    @Test func rejectsIgnoredRangeForNonzeroOffset() async throws {
        await #expect(throws: (any Error).self) {
            try await transport().read(
                source: source("ignored"), range: ByteRange(offset: 4096, length: 4))
        }
    }

    @Test func rejectsTruncatedBody() async throws {
        await #expect(throws: (any Error).self) {
            try await transport().read(
                source: source("truncated"), range: ByteRange(offset: 0, length: 4))
        }
    }

    @Test func rejectsUnboundedOrOverflowingRequests() {
        #expect(throws: (any Error).self) { try ByteRange(offset: 0, length: 8 * 1024 * 1024) }
        #expect(throws: (any Error).self) { try ByteRange(offset: Int64.max, length: 2) }
        #expect(throws: (any Error).self) { try ByteRange(offset: -1, length: 1) }
    }

    @Test func cancelsProducerOnConsumerExit() async throws {
        FixtureURLProtocol.started.withLock { _ = $0.remove("stalled.mp4") }
        FixtureURLProtocol.stopped.withLock { _ = $0.remove("stalled.mp4") }
        let client = transport()
        let input = try source("stalled")
        let task = Task {
            try await client.read(source: input, range: ByteRange(offset: 0, length: 4))
        }
        for _ in 0..<100 where !FixtureURLProtocol.started.withLock({ $0.contains("stalled.mp4") })
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FixtureURLProtocol.started.withLock { $0.contains("stalled.mp4") })
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        // URLSession delivers stopLoading on its own executor after cancellation resumes the caller.
        for _ in 0..<100 where !FixtureURLProtocol.stopped.withLock({ $0.contains("stalled.mp4") })
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FixtureURLProtocol.stopped.withLock { $0.contains("stalled.mp4") })
    }
}
