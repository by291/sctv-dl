import Foundation

public struct NativeTransferID: Codable, Equatable, Hashable, Sendable {
    public let session: String
    public let task: Int
    public init(session: String, task: Int) {
        self.session = session
        self.task = task
    }
}

public struct ResumeReference: Codable, Equatable, Sendable {
    public let relativePath: String
    public init(relativePath: String) { self.relativePath = relativePath }
}

public enum NativeTransferState: Sendable { case running, suspended, completed }

public struct NativeTransfer: Sendable {
    public let id: NativeTransferID
    public let taskID: UUID
    public let attemptID: UUID
    public let state: NativeTransferState

    public init(id: NativeTransferID, taskID: UUID, attemptID: UUID, state: NativeTransferState) {
        self.id = id
        self.taskID = taskID
        self.attemptID = attemptID
        self.state = state
    }
}

public enum TransferEvent: Sendable {
    case progress(
        taskID: UUID, attemptID: UUID, nativeID: NativeTransferID, received: Int64, total: Int64?)
    case staged(StagedFile, nativeID: NativeTransferID)
    case failed(
        taskID: UUID, attemptID: UUID, nativeID: NativeTransferID, reason: String,
        resume: ResumeReference?)
    /// URLSession has delivered its current background callback batch. The app may call the
    /// system completion handler only after earlier events have reached durable storage.
    case drain(identifier: String, token: UUID)
}

public protocol TransferDriver: Sendable {
    /// Starts a native task for this durable attempt. A thrown error may follow native creation;
    /// the coordinator must inspect the native snapshot before starting a replacement.
    func enqueue(_ task: DownloadTask) async throws -> NativeTransferID

    func cancel(_ id: NativeTransferID) async throws

    /// Stops the native transfer and returns a durable resume reference when the platform permits.
    /// A `nil` result permits restart only; a thrown error leaves the native outcome uncertain.
    func pause(_ id: NativeTransferID) async throws -> ResumeReference?

    /// Resumes the same durable attempt. Native callbacks can arrive before this method returns.
    func resume(_ task: DownloadTask, from reference: ResumeReference) async throws
        -> NativeTransferID

    /// Returns the current native tasks for reconciliation, without starting additional transfers.
    func snapshot() async throws -> [NativeTransfer]

    /// Returns an already adopted callback file by durable task and attempt identity.
    func stagedFile(taskID: UUID, attemptID: UUID) async throws -> StagedFile?

    func stagedFiles() async throws -> [StagedFile]

    /// Returns a durable terminal failure receipt, including the native task identity.
    func terminalFailure(taskID: UUID, attemptID: UUID) async throws -> TransferEvent?
    func discardTerminalFailure(taskID: UUID, attemptID: UUID) async throws

    /// Deletes resume artifacts not retained by durable records or an in-flight enqueue/pause.
    func pruneResumeData(keepingAttempts: Set<UUID>) async throws
    func discardResumeData(taskID: UUID, attemptID: UUID) async throws

    /// Streams ordered native callbacks; this is an event stream with no initial snapshot.
    /// The coordinator owns consuming and cancelling its subscription and persisting each event.
    func events() async -> AsyncStream<TransferEvent>

    /// Releases a matching background completion token only after earlier callbacks are durable.
    func acknowledgeDrain(identifier: String, token: UUID) async
}

extension TransferDriver {
    public func stagedFiles() async throws -> [StagedFile] { [] }
    public func terminalFailure(taskID: UUID, attemptID: UUID) async throws -> TransferEvent? {
        nil
    }
    public func discardTerminalFailure(taskID: UUID, attemptID: UUID) async throws {}
    public func pruneResumeData(keepingAttempts: Set<UUID>) async throws {}
    public func discardResumeData(taskID: UUID, attemptID: UUID) async throws {}
    public func acknowledgeDrain(identifier: String, token: UUID) async {}
}
