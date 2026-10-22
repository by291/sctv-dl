import Foundation
import SCTVCore

public final class URLSessionRangeTransport: MediaRangeTransport {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        session = URLSession(
            configuration: configuration, delegate: RedirectRejectionDelegate(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func read(source: MediaSource, range: ByteRange) async throws -> RangeResponse {
        var request = URLRequest(url: try MediaURLPolicy.validate(source.url))
        request.allHTTPHeaderFields = source.headers
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("bytes=\(range.offset)-\(range.end)", forHTTPHeaderField: "Range")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else {
            throw MediaTransportError.invalidResponse
        }
        let metadata = try RangeResponseValidator.validate(response, range: range)

        return try await withTaskCancellationHandler {
            var body = Data()
            body.reserveCapacity(metadata.expectedBytes)
            for try await byte in bytes {
                try Task.checkCancellation()
                guard body.count < metadata.expectedBytes else {
                    throw MediaTransportError.excessiveBody
                }
                body.append(byte)
            }
            guard body.count == metadata.expectedBytes else {
                throw MediaTransportError.truncatedBody
            }
            return RangeResponse(
                data: body, contentLength: metadata.totalBytes, mediaType: metadata.mediaType)
        } onCancel: {
            bytes.task.cancel()
        }
    }
}

private final class RedirectRejectionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
