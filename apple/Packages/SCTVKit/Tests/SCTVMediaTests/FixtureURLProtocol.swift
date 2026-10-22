import Foundation
import Synchronization

final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    static let started = Mutex(Set<String>())
    static let stopped = Mutex(Set<String>())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let name = request.url!.lastPathComponent
        Self.started.withLock { $0.insert(name) }
        let range = request.value(forHTTPHeaderField: "Range") ?? "bytes=0-3"
        let offset = Int(range.dropFirst(6).split(separator: "-")[0])!
        let status = name == "ignored.mp4" ? 200 : 206
        let start = name == "wrong.mp4" ? 0 : offset
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "video/mp4", "Content-Length": "4",
                "Content-Range": "bytes \(start)-\(start + 3)/10000",
            ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let count = name == "truncated.mp4" ? 2 : 4
        client?.urlProtocol(self, didLoad: Data(repeating: 7, count: count))
        if name != "stalled.mp4" { client?.urlProtocolDidFinishLoading(self) }
    }

    override func stopLoading() {
        Self.stopped.withLock { $0.insert(request.url!.lastPathComponent) }
    }
}
