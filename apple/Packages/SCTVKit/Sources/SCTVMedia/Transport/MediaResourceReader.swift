import Foundation
import SCTVCore

@MainActor
public struct MediaResourceReader {
    private let transport: any MediaRangeTransport

    public init(transport: any MediaRangeTransport) {
        self.transport = transport
    }

    /// A zero length requests only metadata; nil streams to the validated end of the resource.
    public func read(
        source: MediaSource, offset: Int64, length: Int?,
        metadata: (Int64, String) -> Void, receive: (Data) -> Void
    ) async throws {
        guard offset >= 0, length == nil || length! >= 0 else {
            throw MediaTransportError.invalidRange
        }
        let first = try await transport.read(
            source: source, range: ByteRange(offset: offset, length: 1))
        try Task.checkCancellation()
        guard first.data.count == 1, first.contentLength > offset else {
            throw MediaTransportError.invalidResponse
        }
        metadata(first.contentLength, first.mediaType)
        if length == 0 { return }

        let remaining = first.contentLength - offset
        let count = min(length.map(Int64.init) ?? remaining, remaining)
        receive(first.data)
        var position = offset + 1
        let end = offset + count

        while position < end {
            try Task.checkCancellation()
            let size = Int(min(Int64(ByteRange.maximumLength), end - position))
            let chunk = try await transport.read(
                source: source, range: ByteRange(offset: position, length: size))
            try Task.checkCancellation()
            guard chunk.contentLength == first.contentLength, chunk.data.count == size else {
                throw MediaTransportError.mismatchedRange
            }
            receive(chunk.data)
            position += Int64(chunk.data.count)
        }
    }
}
