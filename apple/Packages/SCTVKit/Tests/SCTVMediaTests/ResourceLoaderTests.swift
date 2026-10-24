import Foundation
import SCTVCore
import Testing

@testable import SCTVMedia

struct ResourceLoaderTests {
    actor FixtureTransport: MediaRangeTransport {
        let total: Int64 = 2 * 1024 * 1024
        var requestedBytes = 0

        func read(source: MediaSource, range: ByteRange) async throws -> RangeResponse {
            requestedBytes += range.length
            let count = min(range.length, Int(total - range.offset))
            return RangeResponse(
                data: Data(repeating: 1, count: count), contentLength: total, mediaType: "video/mp4"
            )
        }
    }

    @Test @MainActor func boundsBufferedBytes() async throws {
        let transport = FixtureTransport()
        let reader = MediaResourceReader(transport: transport)
        let source = try MediaSource(
            url: URL(string: "https://fscgc.scgchc.com/test.mp4")!, quality: .standard)
        var delivered = 0
        var peak = 0
        try await reader.read(
            source: source, offset: 0, length: nil,
            metadata: { total, _ in
                #expect(total == 2 * 1024 * 1024)
            },
            receive: { data in
                delivered += data.count
                peak = max(peak, data.count)
            })
        #expect(delivered == 2 * 1024 * 1024)
        #expect(peak <= 256 * 1024)
    }

    @Test @MainActor func metadataOnlyDoesNotReadWholeAsset() async throws {
        let transport = FixtureTransport()
        let reader = MediaResourceReader(transport: transport)
        let source = try MediaSource(
            url: URL(string: "https://fscgc.scgchc.com/test.mp4")!, quality: .standard)
        var delivered = 0
        try await reader.read(
            source: source, offset: 0, length: 0, metadata: { _, _ in },
            receive: { delivered += $0.count })
        #expect(delivered == 0)
        #expect(await transport.requestedBytes == 1)
    }
}
