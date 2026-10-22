import Foundation
import SCTVCore

public struct ByteRange: Equatable, Sendable {
    public static let maximumLength = 256 * 1024

    public let offset: Int64
    public let length: Int
    public var end: Int64 { offset + Int64(length) - 1 }

    public init(offset: Int64, length: Int) throws {
        guard offset >= 0, length > 0, length <= Self.maximumLength,
            offset <= Int64.max - Int64(length)
        else { throw MediaTransportError.invalidRange }

        self.offset = offset
        self.length = length
    }
}

public struct RangeResponse: Sendable {
    public let data: Data
    public let contentLength: Int64
    public let mediaType: String

    public init(data: Data, contentLength: Int64, mediaType: String) {
        self.data = data
        self.contentLength = contentLength
        self.mediaType = mediaType
    }
}

public enum MediaTransportError: Error, Equatable {
    case invalidRange
    case invalidResponse
    case unexpectedStatus(Int)
    case mismatchedRange
    case truncatedBody
    case excessiveBody
    case unsupportedEncoding
}

public protocol MediaRangeTransport: Sendable {
    func read(source: MediaSource, range: ByteRange) async throws -> RangeResponse
}
