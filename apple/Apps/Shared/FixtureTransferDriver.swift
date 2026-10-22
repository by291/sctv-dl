#if DEBUG
    import Foundation
    import SCTVCore
    import SCTVDownloads

    /// Deterministic fixture transfers exercise the complete persistence/publication UI path.
    /// Native daemon recovery remains a separate platform acceptance gate.
    actor FixtureTransferDriver: TransferDriver {
        private let staging: DownloadStagingStore
        private var sequence = 0
        private var active: [NativeTransferID: NativeTransfer] = [:]
        private var continuation: AsyncStream<TransferEvent>.Continuation?
        init(staging: URL) throws { self.staging = try DownloadStagingStore(root: staging) }
        func enqueue(_ task: DownloadTask) async throws -> NativeTransferID {
            sequence += 1
            let id = NativeTransferID(session: "fixture", task: sequence)
            active[id] = NativeTransfer(
                id: id, taskID: task.id, attemptID: task.attemptID, state: .running)
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard active[id] != nil else { return }
                do {
                    guard let url = Bundle.main.url(forResource: "probe", withExtension: "mp4")
                    else { throw CocoaError(.fileNoSuchFile) }
                    let callback = FileManager.default.temporaryDirectory.appending(
                        path: UUID().uuidString)
                    try FileManager.default.copyItem(at: url, to: callback)
                    defer { try? FileManager.default.removeItem(at: callback) }
                    let file = try staging.adoptTemporaryFile(
                        at: callback, taskID: task.id, attemptID: task.attemptID)
                    active[id] = nil
                    continuation?.yield(.staged(file, nativeID: id))
                } catch {
                    continuation?.yield(
                        .failed(
                            taskID: task.id, attemptID: task.attemptID, nativeID: id,
                            reason: error.localizedDescription, resume: nil))
                }
            }
            return id
        }
        func cancel(_ id: NativeTransferID) async throws { active[id] = nil }
        func pause(_ id: NativeTransferID) async throws -> ResumeReference? {
            active[id] = nil
            return nil
        }
        func resume(_ task: DownloadTask, from reference: ResumeReference) async throws
            -> NativeTransferID
        { try await enqueue(task) }
        func snapshot() async throws -> [NativeTransfer] { Array(active.values) }
        func stagedFile(taskID: UUID, attemptID: UUID) async throws -> StagedFile? {
            try staging.stagedFile(taskID: taskID, attemptID: attemptID)
        }
        func events() async -> AsyncStream<TransferEvent> { AsyncStream { continuation = $0 } }
    }
#endif
