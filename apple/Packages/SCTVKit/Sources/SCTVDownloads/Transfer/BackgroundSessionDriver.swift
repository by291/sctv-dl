import Foundation
import SCTVCore

public enum BackgroundTransferError: LocalizedError, Sendable {
    case unknownSession
    case invalidResume
    case invalidSource

    public var errorDescription: String? {
        switch self {
        case .unknownSession: "后台下载会话不可用，请重试。"
        case .invalidResume: "续传数据失效，请重新下载。"
        case .invalidSource: "下载地址无效。"
        }
    }
}

public actor BackgroundSessionDriver: TransferDriver {
    public static let sessionPrefix = "dev.sctvdl.apple.downloads"
    public static let cellularAllowedIdentifier = "\(sessionPrefix).cellular-allowed"
    public static let cellularDisallowedIdentifier = "\(sessionPrefix).cellular-disallowed"

    private let staging: DownloadStagingStore
    private let resumes: ResumeDataStore
    private let failures: TerminalFailureStore
    private var sessions: [String: URLSession] = [:]
    private var delegates: [String: BackgroundSessionDelegate] = [:]
    private var continuation: AsyncStream<TransferEvent>.Continuation?
    private var pendingEvents: [TransferEvent] = []
    private var completions: [String: @MainActor @Sendable () -> Void] = [:]
    private var acknowledgedIdentifiers: Set<String> = []
    private var drainTokens: [String: UUID] = [:]

    public init(stagingRoot: URL, resumeRoot: URL) throws {
        staging = try DownloadStagingStore(root: stagingRoot)
        resumes = try ResumeDataStore(root: resumeRoot)
        failures = try TerminalFailureStore(root: resumeRoot.appending(path: "Failures"))
    }

    /// Call before queue reconciliation at every launch. The fixed pair is reused for all tasks.
    public func restoreSessions() {
        guard sessions.isEmpty else { return }
        for (identifier, allowsCellular) in [
            (Self.cellularAllowedIdentifier, true),
            (Self.cellularDisallowedIdentifier, false),
        ] {
            let configuration = Self.configuration(allowsCellular: allowsCellular)
            let delegate = BackgroundSessionDelegate(
                identifier: identifier, staging: staging, resumes: resumes, failures: failures)
            delegate.attach(self)
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(
                configuration: configuration, delegate: delegate, delegateQueue: queue)
            delegates[identifier] = delegate
            sessions[identifier] = session
        }
    }

    public func enqueue(_ task: DownloadTask) async throws -> NativeTransferID {
        restoreSessions()
        let session = try session(for: task.allowsCellular)
        let request = try Self.request(for: task)
        let native = session.downloadTask(with: request)
        native.taskDescription = TransferCorrelation(task).taskDescription
        native.resume()
        return NativeTransferID(
            session: Self.identifier(allowsCellular: task.allowsCellular),
            task: native.taskIdentifier)
    }

    public func cancel(_ id: NativeTransferID) async throws {
        restoreSessions()
        guard let task = try await task(for: id) else { return }
        delegates[id.session]?.suppress(id.task)
        task.cancel()
    }

    public func pause(_ id: NativeTransferID) async throws -> ResumeReference? {
        restoreSessions()
        guard let task = try await task(for: id) as? URLSessionDownloadTask,
            let correlation = TransferCorrelation.decode(task.taskDescription)
        else { return nil }
        delegates[id.session]?.suppress(id.task)
        let data = await withCheckedContinuation { continuation in
            task.cancel { data in continuation.resume(returning: data) }
        }
        guard let data else { return nil }
        return try resumes.save(
            data, taskID: correlation.taskID, attemptID: correlation.attemptID)
    }

    public func resume(_ task: DownloadTask, from reference: ResumeReference) async throws
        -> NativeTransferID
    {
        restoreSessions()
        _ = try MediaURLPolicy.validate(task.source.url)
        let data: Data
        do {
            data = try resumes.load(reference, taskID: task.id, attemptID: task.attemptID)
        } catch {
            throw BackgroundTransferError.invalidResume
        }
        let session = try session(for: task.allowsCellular)
        let native = session.downloadTask(withResumeData: data)
        native.taskDescription = TransferCorrelation(task).taskDescription
        native.resume()
        return NativeTransferID(
            session: Self.identifier(allowsCellular: task.allowsCellular),
            task: native.taskIdentifier)
    }

    public func snapshot() async throws -> [NativeTransfer] {
        restoreSessions()
        var result: [NativeTransfer] = []
        for (identifier, session) in sessions {
            for task in await allTasks(in: session) {
                guard let correlation = TransferCorrelation.decode(task.taskDescription) else {
                    // A native task without durable identity cannot be safely attached.
                    task.cancel()
                    continue
                }
                let state: NativeTransferState
                switch task.state {
                case .running: state = .running
                case .suspended: state = .suspended
                case .canceling, .completed: state = .completed
                @unknown default: state = .completed
                }
                result.append(
                    NativeTransfer(
                        id: NativeTransferID(session: identifier, task: task.taskIdentifier),
                        taskID: correlation.taskID, attemptID: correlation.attemptID, state: state))
            }
        }
        return result
    }

    public func stagedFile(taskID: UUID, attemptID: UUID) async throws -> StagedFile? {
        try staging.stagedFile(taskID: taskID, attemptID: attemptID)
    }

    public func stagedFiles() async throws -> [StagedFile] {
        try staging.stagedFiles()
    }

    public func terminalFailure(taskID: UUID, attemptID: UUID) async throws -> TransferEvent? {
        try failures.event(taskID: taskID, attemptID: attemptID)
    }

    public func discardTerminalFailure(taskID: UUID, attemptID: UUID) async throws {
        try failures.remove(taskID: taskID, attemptID: attemptID)
    }

    public func pruneResumeData(keepingAttempts: Set<UUID>) async throws {
        try resumes.prune(keepingAttempts: keepingAttempts)
    }

    public func discardResumeData(taskID: UUID, attemptID: UUID) async throws {
        try resumes.remove(taskID: taskID, attemptID: attemptID)
    }

    public func events() async -> AsyncStream<TransferEvent> {
        AsyncStream { continuation in
            self.continuation?.finish()
            self.continuation = continuation
            for event in pendingEvents { continuation.yield(event) }
            pendingEvents.removeAll()
        }
    }

    /// Called by the app delegate; the completion is held until the queue acknowledges a drain.
    public func registerBackgroundCompletion(
        identifier: String, completion: @escaping @MainActor @Sendable () -> Void
    ) async {
        restoreSessions()
        guard sessions[identifier] != nil else { return }
        if acknowledgedIdentifiers.remove(identifier) != nil {
            await completion()
        } else {
            completions[identifier] = completion
        }
    }

    public func acknowledgeDrain(identifier: String, token: UUID) async {
        guard drainTokens[identifier] == token else { return }
        drainTokens.removeValue(forKey: identifier)
        if let completion = completions.removeValue(forKey: identifier) {
            await completion()
        } else {
            acknowledgedIdentifiers.insert(identifier)
        }
    }

    func emit(_ event: TransferEvent) {
        let identifier: String
        switch event {
        case .progress(_, _, let nativeID, _, _), .staged(_, let nativeID),
            .failed(_, _, let nativeID, _, _):
            identifier = nativeID.session
        case .drain(let session, _):
            identifier = session
        }
        // An acknowledgement is credit for one finished batch only. New callbacks revoke it.
        acknowledgedIdentifiers.remove(identifier)
        drainTokens.removeValue(forKey: identifier)
        if case .drain(_, let token) = event {
            drainTokens[identifier] = token
        }
        if let continuation { continuation.yield(event) } else { pendingEvents.append(event) }
    }

    static func identifier(allowsCellular: Bool) -> String {
        allowsCellular ? cellularAllowedIdentifier : cellularDisallowedIdentifier
    }

    static func configuration(allowsCellular: Bool) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: identifier(allowsCellular: allowsCellular))
        configuration.allowsCellularAccess = allowsCellular
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 4
        #if os(iOS)
            configuration.sessionSendsLaunchEvents = true
        #endif
        return configuration
    }

    static func request(for task: DownloadTask) throws -> URLRequest {
        // Validate the initial media URL. Background URLSession follows redirects under
        // system control; its delegate cannot enforce the foreground transport's redirect ban.
        let url = try MediaURLPolicy.validate(task.source.url)
        var request = URLRequest(url: url)
        for header in ["Referer", "User-Agent"] {
            if let value = task.source.headers[header],
                !value.contains("\r"), !value.contains("\n")
            {
                request.setValue(value, forHTTPHeaderField: header)
            }
        }
        return request
    }

    private func session(for allowsCellular: Bool) throws -> URLSession {
        guard let session = sessions[Self.identifier(allowsCellular: allowsCellular)] else {
            throw BackgroundTransferError.unknownSession
        }
        return session
    }

    private func task(for id: NativeTransferID) async throws -> URLSessionTask? {
        guard let session = sessions[id.session] else {
            throw BackgroundTransferError.unknownSession
        }
        return await allTasks(in: session).first { $0.taskIdentifier == id.task }
    }

    private func allTasks(in session: URLSession) async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
    }
}
