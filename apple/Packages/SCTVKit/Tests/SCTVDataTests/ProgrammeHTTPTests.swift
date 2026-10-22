import Foundation
import SCTVCore
import Testing

@testable import SCTVData

@Suite(.serialized) struct ProgrammeHTTPTests {
    @Test func boundsChunkedMetadataBeforeBuffering() async throws {
        let limit = 2 * 1024 * 1024
        let chunks = AsyncStream<Data> { continuation in
            continuation.yield(Data(repeating: 1, count: limit))
            continuation.yield(Data([2]))
            continuation.finish()
        }
        var receivedAcceptedBytes = 0
        do {
            _ = try await BoundedHTTPBody.read(chunks, limit: limit) { receivedAcceptedBytes = $0 }
            Issue.record("Body beyond limit was accepted")
        } catch BoundedHTTPBody.BodyError.tooLarge {
            #expect(receivedAcceptedBytes <= 2 * 1024 * 1024)
            #expect(receivedAcceptedBytes == limit)
        }
    }

    @Test func guestProfileIsLimitedToMetadataRequests() async throws {
        let profile = GuestRequestProfile(
            deviceID: UUID(uuidString: "EBD43827-9F2E-49CA-BAAF-87C9E6542807")!)
        let request = profile.apply(
            to: URLRequest(url: URL(string: "https://gw.scgchc.com/app/v1/programs")!))
        #expect(
            request.value(forHTTPHeaderField: "deviceId") == "EBD43827-9F2E-49CA-BAAF-87C9E6542807")
        #expect(request.value(forHTTPHeaderField: "appVersion") == "9.6.1.5")
        #expect(request.value(forHTTPHeaderField: "deviceType") == "android")
    }

    @Test func reportsHTTPAndBusinessErrors() async throws {
        let client = try makeClient()
        MetadataURLProtocol.mode = .headersOnly(status: 503)
        MetadataURLProtocol.resetStops()
        await #expect(throws: ProgrammeHTTPError.httpStatus(503)) { try await client.catalogue() }
        try await waitForStop()
        #expect(MetadataURLProtocol.stopCount > 0)

        MetadataURLProtocol.mode = .response(
            status: 200, body: Data(#"{"rs":401,"error":"guest denied","data":null}"#.utf8))
        await #expect(throws: ProgrammeDecodingError.businessError("guest denied")) {
            try await client.catalogue()
        }
    }

    @Test func cancelsNetworkAfterMetadataOverflow() async throws {
        MetadataURLProtocol.mode = .oversizedBody
        MetadataURLProtocol.resetStops()
        let client = try makeClient()
        await #expect(throws: BoundedHTTPBody.BodyError.tooLarge) { try await client.catalogue() }
        try await waitForStop()
        #expect(MetadataURLProtocol.stopCount > 0)
    }

    @Test func rejectsRedirects() async throws {
        MetadataURLProtocol.mode = .redirect
        let client = try makeClient()
        await #expect(throws: (any Error).self) { try await client.catalogue() }
    }

    @Test func keepsHeaderAndBodyDeadlinesIndependent() async throws {
        let client = try makeClient(
            headerDeadline: .milliseconds(30), bodyDeadline: .milliseconds(30))
        MetadataURLProtocol.mode = .delayedHeaders
        MetadataURLProtocol.resetStops()
        await #expect(throws: ProgrammeHTTPError.deadline) { try await client.catalogue() }
        try await waitForStop()
        #expect(MetadataURLProtocol.stopCount > 0)

        MetadataURLProtocol.mode = .delayedBody
        MetadataURLProtocol.resetStops()
        await #expect(throws: ProgrammeHTTPError.deadline) { try await client.catalogue() }
        try await waitForStop()
        #expect(MetadataURLProtocol.stopCount > 0)
    }

    @Test func shortBodyDeadlinesAlwaysReportTimeoutAndCancelTask() async throws {
        let client = try makeClient(bodyDeadline: .milliseconds(5))
        MetadataURLProtocol.mode = .delayedBody
        for _ in 0..<25 {
            MetadataURLProtocol.resetStops()
            await #expect(throws: ProgrammeHTTPError.deadline) { try await client.catalogue() }
            try await waitForStop()
            #expect(MetadataURLProtocol.stopCount > 0)
        }
    }

    @Test func cancellationStopsBodyRead() async throws {
        MetadataURLProtocol.mode = .delayedBody
        let client = try makeClient(bodyDeadline: .seconds(2))
        let pending = Task { try await client.catalogue() }
        try await Task.sleep(for: .milliseconds(30))
        pending.cancel()
        await #expect(throws: (any Error).self) { try await pending.value }
    }

    private func makeClient(
        headerDeadline: Duration = .seconds(2),
        bodyDeadline: Duration = .seconds(2)
    ) throws -> ProgrammeHTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MetadataURLProtocol.self]
        let session = URLSession(configuration: config)
        let location = FileManager.default.temporaryDirectory.appending(
            path: "b1-identity-\(UUID().uuidString)")
        return try ProgrammeHTTPClient(
            session: session,
            identity: InstallationIdentity(location: location),
            headerDeadline: headerDeadline,
            bodyDeadline: bodyDeadline
        )
    }

    private func waitForStop() async throws {
        for _ in 0..<20 where MetadataURLProtocol.stopCount == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private final class MetadataURLProtocol: URLProtocol, @unchecked Sendable {
    enum Mode: Sendable {
        case response(status: Int, body: Data)
        case headersOnly(status: Int)
        case oversizedBody
        case redirect, delayedHeaders, delayedBody
    }
    nonisolated(unsafe) static var mode: Mode = .response(status: 200, body: Data())
    private static let stopLock = NSLock()
    nonisolated(unsafe) private static var stops = 0
    static var stopCount: Int {
        stopLock.lock()
        defer { stopLock.unlock() }
        return stops
    }
    static func resetStops() {
        stopLock.lock()
        defer { stopLock.unlock() }
        stops = 0
    }
    private var work: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let mode = Self.mode
        work = Task {
            switch mode {
            case .response(let status, let body):
                reply(status: status, body: body)
            case .headersOnly(let status):
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(repeating: 1, count: 64 * 1024))
            case .oversizedBody:
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(
                    self, didLoad: Data(repeating: 1, count: BoundedHTTPBody.metadataLimit + 1))
            case .redirect:
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 302, httpVersion: nil,
                    headerFields: ["Location": "https://example.com/elsewhere"])!
                client?.urlProtocol(
                    self,
                    wasRedirectedTo: URLRequest(url: URL(string: "https://example.com/elsewhere")!),
                    redirectResponse: response)
                client?.urlProtocolDidFinishLoading(self)
            case .delayedHeaders:
                try? await Task.sleep(for: .milliseconds(200))
                if !Task.isCancelled {
                    reply(status: 200, body: Data(#"{"rs":200,"data":{"records":[]}}"#.utf8))
                }
            case .delayedBody:
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(repeating: 32, count: 64 * 1024))
                try? await Task.sleep(for: .milliseconds(200))
                if !Task.isCancelled {
                    client?.urlProtocol(
                        self, didLoad: Data(#"{"rs":200,"data":{"records":[]}}"#.utf8))
                    client?.urlProtocolDidFinishLoading(self)
                }
            }
        }
    }

    override func stopLoading() {
        Self.stopLock.lock()
        Self.stops += 1
        Self.stopLock.unlock()
        work?.cancel()
    }

    private func reply(status: Int, body: Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
