import Foundation
import SCTVCore

@testable import SCTVMedia

struct FixtureFileTransport: MediaRangeTransport {
    let url: URL

    func read(source: MediaSource, range: ByteRange) async throws -> RangeResponse {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let total = try file.seekToEnd()
        try file.seek(toOffset: UInt64(range.offset))
        return RangeResponse(
            data: try file.read(upToCount: range.length) ?? Data(), contentLength: Int64(total),
            mediaType: "video/mp4")
    }
}
