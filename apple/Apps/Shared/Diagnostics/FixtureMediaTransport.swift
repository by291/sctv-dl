#if DEBUG
    import Foundation
    import SCTVCore
    import SCTVMedia

    /// Debug-only synthetic source. Production URL validation is never relaxed for a localhost fixture.
    struct FixtureMediaTransport: MediaRangeTransport {
        func read(source: MediaSource, range: ByteRange) async throws -> RangeResponse {
            guard let url = Bundle.main.url(forResource: "probe", withExtension: "mp4") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let total = try file.seekToEnd()
            try file.seek(toOffset: UInt64(range.offset))
            return RangeResponse(
                data: try file.read(upToCount: range.length) ?? Data(), contentLength: Int64(total),
                mediaType: "video/mp4")
        }
    }
#endif
