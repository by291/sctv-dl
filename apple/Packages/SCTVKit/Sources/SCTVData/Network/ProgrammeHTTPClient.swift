import Foundation
import SCTVCore

public enum ProgrammeHTTPError: Error, Equatable, Sendable {
    case forbiddenEndpoint
    case invalidID
    case redirected
    case httpStatus(Int)
    case deadline
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public struct ProgrammeHTTPClient: ProgrammeAPI {
    private let session: URLSession
    private let identity: InstallationIdentity
    private let base: URL
    private let headerDeadline: Duration
    private let bodyDeadline: Duration
    private let redirectDelegate = RejectRedirects()

    public init(
        session: URLSession = .shared,
        identity: InstallationIdentity,
        base: URL = URL(string: "https://gw.scgchc.com")!,
        headerDeadline: Duration = .seconds(20),
        bodyDeadline: Duration = .seconds(20)
    ) throws {
        guard base.scheme == "https", base.host() == "gw.scgchc.com", base.port == nil,
            base.user() == nil, base.password() == nil
        else { throw ProgrammeHTTPError.forbiddenEndpoint }
        self.session = session
        self.identity = identity
        self.base = base
        self.headerDeadline = headerDeadline
        self.bodyDeadline = bodyDeadline
    }

    public func catalogue() async throws -> [Programme] {
        try ProgrammeDecoder.decodeCatalogue(await request("/app/v1/programs?page=0&size=100"))
    }

    public func dates(programmeID: String) async throws -> [BroadcastDate] {
        guard ProgrammeDecoder.validID(programmeID) else { throw ProgrammeHTTPError.invalidID }
        return try ProgrammeDecoder.decodeDates(
            await request("/app/v1/programs/\(programmeID)/dates/list"))
    }

    public func contents(programmeID: String, dateID: String) async throws -> [ProgrammeContent] {
        guard ProgrammeDecoder.validID(programmeID), ProgrammeDecoder.validID(dateID) else {
            throw ProgrammeHTTPError.invalidID
        }
        return try ProgrammeDecoder.decodeContents(
            await request("/app/v1/programs/\(programmeID)/dates/\(dateID)/contents/list"))
    }

    private func request(_ path: String) async throws -> Data {
        let deviceID = try await identity.get()
        let url = URL(string: path, relativeTo: base)!.absoluteURL
        let original = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let request = GuestRequestProfile(deviceID: deviceID).apply(to: original)

        // Each deadline owns only its phase. Cancelling the parent task cancels URLSession reads.
        let (bytes, response) = try await withDeadline(after: headerDeadline) {
            try await session.bytes(for: request, delegate: redirectDelegate)
        }
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else {
            throw ProgrammeHTTPError.forbiddenEndpoint
        }
        guard !(300...399).contains(http.statusCode) else { throw ProgrammeHTTPError.redirected }
        guard (200...299).contains(http.statusCode) else {
            throw ProgrammeHTTPError.httpStatus(http.statusCode)
        }
        return try await withTaskCancellationHandler {
            try await withDeadline(after: bodyDeadline) {
                try await BoundedHTTPBody.read(bytes)
            }
        } onCancel: {
            bytes.task.cancel()
        }
    }
}

private func withDeadline<T: Sendable>(
    after duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw ProgrammeHTTPError.deadline
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
