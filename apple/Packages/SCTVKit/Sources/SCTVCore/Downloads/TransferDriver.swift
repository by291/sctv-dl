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
    func enqueue(_ task: DownloadTask) async throws -> NativeTransferID
    func cancel(_ id: NativeTransferID) async throws
    func pause(_ id: NativeTransferID) async throws -> ResumeReference?
    func resume(_ task: DownloadTask, from reference: ResumeReference) async throws
        -> NativeTransferID
    func snapshot() async throws -> [NativeTransfer]
    /// Returns an already adopted callback file by durable task and attempt identity.
    func stagedFile(taskID: UUID, attemptID: UUID) async throws -> StagedFile?
    func stagedFiles() async throws -> [StagedFile]
    /// Returns a durable terminal failure receipt, including the native task identity.
    func terminalFailure(taskID: UUID, attemptID: UUID) async throws -> TransferEvent?
    func discardTerminalFailure(taskID: UUID, attemptID: UUID) async throws
    func pruneResumeData(keepingAttempts: Set<UUID>) async throws
    func discardResumeData(taskID: UUID, attemptID: UUID) async throws
    func events() async -> AsyncStream<TransferEvent>
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
