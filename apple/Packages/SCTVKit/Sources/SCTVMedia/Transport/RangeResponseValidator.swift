import Foundation

struct RangeResponseMetadata {
    let expectedBytes: Int
    let totalBytes: Int64
    let mediaType: String
}

enum RangeResponseValidator {
    static func validate(_ response: HTTPURLResponse, range: ByteRange) throws
        -> RangeResponseMetadata
    {
        let encoding = response.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
        guard encoding == nil || encoding == "identity" else {
            throw MediaTransportError.unsupportedEncoding
        }
        guard let type = response.mimeType,
            type.hasPrefix("video/") || type == "application/octet-stream"
        else { throw MediaTransportError.invalidResponse }

        if response.statusCode == 200 {
            // A small complete object is safe only at zero; never treat a full body as a later range.
            let length = response.expectedContentLength
            guard range.offset == 0, length > 0, length <= range.length else {
                throw MediaTransportError.mismatchedRange
            }
            return RangeResponseMetadata(
                expectedBytes: Int(length), totalBytes: length, mediaType: type)
        }

        guard response.statusCode == 206 else {
            throw MediaTransportError.unexpectedStatus(response.statusCode)
        }
        guard let header = response.value(forHTTPHeaderField: "Content-Range"),
            header.hasPrefix("bytes ")
        else {
            throw MediaTransportError.mismatchedRange
        }
        let parts = header.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let total = Int64(parts[1]), total > 0 else {
            throw MediaTransportError.mismatchedRange
        }
        let bounds = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = Int64(bounds[0]), let end = Int64(bounds[1]),
            start == range.offset, start < total, end == min(range.end, total - 1), end >= start
        else { throw MediaTransportError.mismatchedRange }

        let count = Int(end - start + 1)
        guard response.expectedContentLength < 0 || response.expectedContentLength == count else {
            throw MediaTransportError.mismatchedRange
        }
        return RangeResponseMetadata(expectedBytes: count, totalBytes: total, mediaType: type)
    }
}
