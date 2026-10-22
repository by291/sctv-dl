import Foundation

public enum BoundedHTTPBody {
    public enum BodyError: Error, Sendable { case tooLarge }
    public static let metadataLimit = 2 * 1024 * 1024

    public static func read<S: AsyncSequence>(
        _ chunks: S,
        limit: Int = metadataLimit,
        onAccepted: (Int) -> Void = { _ in }
    ) async throws -> Data where S.Element == Data {
        var result = Data()
        for try await chunk in chunks {
            guard chunk.count <= limit - result.count else { throw BodyError.tooLarge }
            result.append(chunk)
            onAccepted(result.count)
        }
        return result
    }

    static func read(_ bytes: URLSession.AsyncBytes, limit: Int = metadataLimit) async throws
        -> Data
    {
        var result = Data()
        for try await byte in bytes {
            guard result.count < limit else { throw BodyError.tooLarge }
            result.append(byte)
        }
        return result
    }
}
