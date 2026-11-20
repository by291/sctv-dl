import Foundation
import SCTVCore
import SCTVTestSupport
import Synchronization
import Testing

@testable import SCTVData

@Suite(.serialized) final class ProgrammeHTTPTests {
    private let identityLocation = FileManager.default.temporaryDirectory.appending(
        path: "metadata-identity-\(UUID().uuidString)")

    deinit {
        try? FileManager.default.removeItem(at: identityLocation)
    }

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
        let failure = MetadataURLProtocol.install(.headersOnly(status: 503))
        await #expect(throws: ProgrammeHTTPError.httpStatus(503)) { try await client.catalogue() }
        try await waitForStop(failure)

        MetadataURLProtocol.install(
            .response(
                status: 200, body: Data(#"{"rs":401,"error":"guest denied","data":null}"#.utf8)))
        await #expect(throws: ProgrammeDecodingError.businessError("guest denied")) {
            try await client.catalogue()
        }
    }

    @Test func cancelsNetworkAfterMetadataOverflow() async throws {
        let request = MetadataURLProtocol.install(.oversizedBody)
        let client = try makeClient()
        await #expect(throws: BoundedHTTPBody.BodyError.tooLarge) { try await client.catalogue() }
        try await waitForStop(request)
    }

    @Test func rejectsRedirectsWithoutRequestingSuccessfulDestination() async throws {
        let redirect = MetadataURLProtocol.install(.redirect)
        let client = try makeClient()

        await #expect(throws: ProgrammeHTTPError.redirected) { try await client.catalogue() }
        #expect(redirect.events.redirectTargetHits == 0)
    }

    @Test func keepsHeaderAndBodyDeadlinesIndependent() async throws {
        let client = try makeClient(
            headerDeadline: .milliseconds(30), bodyDeadline: .milliseconds(30))
        let headers = MetadataURLProtocol.install(.stalledHeaders)
        await #expect(throws: ProgrammeHTTPError.deadline) { try await client.catalogue() }
        try await waitForStop(headers)
        #expect(!headers.events.hasStartedBody)

        let body = MetadataURLProtocol.install(.stalledBody)
        await #expect(throws: ProgrammeHTTPError.deadline) { try await client.catalogue() }
        try await waitForStop(body)
        #expect(body.events.hasStartedBody)
    }

    @Test func shortBodyDeadlinesAlwaysReportTimeoutAndCancelTask() async throws {
        let client = try makeClient(bodyDeadline: .milliseconds(5))
        for _ in 0..<25 {
            let request = MetadataURLProtocol.install(.stalledBody)
            await #expect(throws: ProgrammeHTTPError.deadline) { try await client.catalogue() }
            try await waitForStop(request)
        }
    }

    @Test func cancellationStopsAnInFlightBodyRead() async throws {
        let request = MetadataURLProtocol.install(.stalledBody)
        let client = try makeClient()
        let pending = Task { try await client.catalogue() }

        do {
            try await waitForTestCondition("metadata body to start") {
                request.events.hasStartedBody
            }
            #expect(!request.events.hasStopped)
            pending.cancel()
            try await waitForStop(request)
        } catch {
            pending.cancel()
            _ = await pending.result
            throw error
        }

        switch await pending.result {
        case .failure(is CancellationError):
            break
        case .failure(let error as URLError):
            #expect(error.code == .cancelled)
        case .failure(let error):
            Issue.record("Expected cancellation, received \(error)")
        case .success:
            Issue.record("The cancelled request returned a catalogue")
        }
    }

    private func makeClient(
        headerDeadline: Duration = .seconds(2),
        bodyDeadline: Duration = .seconds(2)
    ) throws -> ProgrammeHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MetadataURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return try ProgrammeHTTPClient(
            session: session,
            identity: InstallationIdentity(location: identityLocation),
            headerDeadline: headerDeadline,
            bodyDeadline: bodyDeadline
        )
    }

    private func waitForStop(_ scenario: MetadataURLProtocol.Scenario) async throws {
        try await waitForTestCondition("URLProtocol.stopLoading") {
            scenario.events.hasStopped
        }
    }
}

private final class MetadataURLProtocol: URLProtocol, @unchecked Sendable {
    private static let redirectTarget = URL(string: "https://example.com/catalogue")!
    private static let validCatalogue = Data(#"{"rs":200,"data":{"records":[]}}"#.utf8)
    private static let partialBodySize = 64 * 1024
    private static let activeScenario = Mutex(Scenario(.stalledHeaders))

    enum Mode: Sendable {
        case response(status: Int, body: Data)
        case headersOnly(status: Int)
        case oversizedBody
        case redirect
        case stalledHeaders
        case stalledBody
    }

    struct Events: Sendable {
        var hasStartedBody = false
        var hasStopped = false
        var redirectTargetHits = 0
    }

    final class Scenario: Sendable {
        let mode: Mode
        private let observed = Mutex(Events())
        var events: Events { observed.withLock { $0 } }

        init(_ mode: Mode) {
            self.mode = mode
        }

        func recordBodyStart() {
            observed.withLock { $0.hasStartedBody = true }
        }

        func recordStop() {
            observed.withLock { $0.hasStopped = true }
        }

        func recordRedirectTargetHit() {
            observed.withLock { $0.redirectTargetHits += 1 }
        }
    }

    // Each URLProtocol instance retains its own scenario so late stops cannot affect the next test.
    private let loadingScenario = Mutex<Scenario?>(nil)

    @discardableResult
    static func install(_ mode: Mode) -> Scenario {
        let scenario = Scenario(mode)
        activeScenario.withLock { $0 = scenario }
        return scenario
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let scenario = Self.activeScenario.withLock { $0 }
        loadingScenario.withLock { $0 = scenario }

        if request.url == Self.redirectTarget {
            scenario.recordRedirectTargetHit()
            reply(status: 200, body: Self.validCatalogue)
            return
        }

        switch scenario.mode {
        case .response(let status, let body):
            reply(status: status, body: body)
        case .headersOnly(let status):
            sendHeaders(status: status)
            sendBody(Data(repeating: 32, count: Self.partialBodySize))
        case .oversizedBody:
            sendHeaders(status: 200)
            sendBody(Data(repeating: 1, count: BoundedHTTPBody.metadataLimit + 1))
            scenario.recordBodyStart()
        case .redirect:
            redirect()
        case .stalledHeaders:
            break
        case .stalledBody:
            sendHeaders(status: 200)
            sendBody(Data(repeating: 32, count: Self.partialBodySize))
            scenario.recordBodyStart()
        }
    }

    override func stopLoading() {
        loadingScenario.withLock { $0 }?.recordStop()
    }

    private func redirect() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 302, httpVersion: nil,
            headerFields: ["Location": Self.redirectTarget.absoluteString])!
        client?.urlProtocol(
            self, wasRedirectedTo: URLRequest(url: Self.redirectTarget), redirectResponse: response)
        // If URLSession refuses the redirect, it still receives the original 302 response.
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func reply(status: Int, body: Data) {
        sendHeaders(status: status)
        sendBody(body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func sendHeaders(status: Int) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    private func sendBody(_ body: Data) {
        client?.urlProtocol(self, didLoad: body)
    }
}
