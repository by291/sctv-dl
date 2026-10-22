import Foundation
import SCTVCore

public actor DownloadCoordinator: DownloadService {
    private let repository: any DownloadRepository
    private let transfer: any TransferDriver
    private let publisher: any FilePublisher
    private var observers: [UUID: AsyncStream<DownloadSnapshot>.Continuation] = [:]
    private var publishing: Set<UUID> = []
    private var reservingBatches = 0
    private var enqueuingAttempts: Set<UUID> = []
    private var pendingEarlyFailures: [UUID: TransferEvent] = [:]
    private var pausingAttempts: Set<UUID> = []
    private var snapshotRevision: UInt64 = 0
    private var publicationGeneration: UInt64 = 0
    private var eventTask: Task<Void, Never>?

    public init(
        repository: any DownloadRepository, transfer: any TransferDriver,
        publisher: any FilePublisher
    ) {
        self.repository = repository
        self.transfer = transfer
        self.publisher = publisher
    }

    deinit { eventTask?.cancel() }

    public func start(_ requests: [DownloadRequest]) async -> DownloadBatchResult {
        let identities = Set(
            requests.map {
                "\($0.content.programmeID)/\($0.content.dateID)/\($0.content.contentID)/\($0.source.quality.rawValue)"
            })
        guard identities.count <= 100 else {
            return .init(
                accepted: [],
                failures: requests.map { .init(content: $0.content, reason: .batchTooLarge) })
        }
        reservingBatches += 1
        defer { reservingBatches -= 1 }
        var accepted: [UUID] = []
        var failures: [DownloadItemFailure] = []
        var seen: Set<String> = []
        for request in requests {
            let key =
                "\(request.content.programmeID)/\(request.content.dateID)/\(request.content.contentID)/\(request.source.quality.rawValue)"
            guard seen.insert(key).inserted else {
                failures.append(.init(content: request.content, reason: .duplicate))
                continue
            }
            do {
                let reserved = try await repository.reserve(request)
                accepted.append(reserved.id)
                enqueuingAttempts.insert(reserved.attemptID)
                await publish()
                await enqueue(reserved)
                enqueuingAttempts.remove(reserved.attemptID)
                if pendingEarlyFailures[reserved.attemptID] != nil {
                    try? await reconcile()
                }
            } catch is DownloadReservationError {
                failures.append(.init(content: request.content, reason: .duplicate))
            } catch {
                failures.append(
                    .init(content: request.content, reason: .storage(error.localizedDescription)))
            }
        }
        return .init(accepted: accepted, failures: failures)
    }

    public func perform(_ commands: [DownloadCommand]) async -> DownloadBatchResult {
        guard Set(commands.map(\.taskID)).count <= 100 else {
            return .init(
                accepted: [],
                failures: commands.map { .init(taskID: $0.taskID, reason: .batchTooLarge) })
        }
        var accepted: [UUID] = []
        var failures: [DownloadItemFailure] = []
        for command in commands {
            do {
                guard var task = try await repository.task(command.taskID) else {
                    failures.append(.init(taskID: command.taskID, reason: .staleAttempt))
                    continue
                }
                if case .interrupted = task.state {
                    // A thrown enqueue may already have created a system task.
                    try await reconcile()
                    guard let refreshed = try await repository.task(command.taskID),
                        refreshed.attemptID == command.expectedAttempt
                    else {
                        failures.append(.init(taskID: command.taskID, reason: .staleAttempt))
                        continue
                    }
                    task = refreshed
                }
                guard task.attemptID == command.expectedAttempt else {
                    failures.append(.init(taskID: command.taskID, reason: .staleAttempt))
                    continue
                }
                guard DownloadTransition.allows(command.action, in: task.state) else {
                    failures.append(.init(taskID: command.taskID, reason: .unavailableAction))
                    continue
                }
                if case .retry = command.action, case .interrupted = task.state,
                    task.nativeID != nil
                {
                    failures.append(.init(taskID: task.id, reason: .unavailableAction))
                    continue
                }
                let changed = try await perform(command.action, task: task)
                if changed {
                    accepted.append(task.id)
                } else {
                    failures.append(.init(taskID: task.id, reason: .staleAttempt))
                }
            } catch {
                failures.append(
                    .init(taskID: command.taskID, reason: .storage(error.localizedDescription)))
            }
        }
        return .init(accepted: accepted, failures: failures)
    }

    public func updates() async -> AsyncStream<DownloadSnapshot> {
        let id = UUID()
        let stream = AsyncStream<DownloadSnapshot>(bufferingPolicy: .bufferingNewest(1)) {
            continuation in
            observers[id] = continuation
            continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) }
            }
        }
        await publish()
        return stream
    }

    @discardableResult
    public func receive(_ event: TransferEvent) async -> Bool {
        do {
            switch event {
            case .progress(let taskID, let attemptID, let nativeID, let received, let total):
                guard let task = try await current(taskID, attemptID, nativeID), received >= 0
                else { return true }
                guard case .transferring = task.state else { return true }
                _ = try await change(
                    task, state: .transferring(received: received, total: total), nativeID: nativeID
                )
            case .staged(let staged, let nativeID):
                guard let task = try await current(staged.taskID, staged.attemptID, nativeID) else {
                    if let task = try await repository.task(staged.taskID),
                        task.attemptID == staged.attemptID
                    {
                        if case .cancelled = task.state {
                            try? await publisher.cleanup(staged)
                        } else {
                            _ = try await recoverStaged(
                                taskID: staged.taskID, attemptID: staged.attemptID)
                        }
                    } else {
                        try? await publisher.cleanup(staged)
                    }
                    return true
                }
                guard try await change(task, state: .publishing(staged)) else { return true }
                pendingEarlyFailures.removeValue(forKey: staged.attemptID)
                try? await transfer.discardResumeData(
                    taskID: staged.taskID, attemptID: staged.attemptID)
                try? await transfer.discardTerminalFailure(
                    taskID: staged.taskID, attemptID: staged.attemptID)
                if let publishing = try await repository.task(task.id) {
                    await publish(staged, for: publishing)
                }
            case .failed(let taskID, let attemptID, let nativeID, let reason, let resume):
                guard let task = try await current(taskID, attemptID, nativeID) else {
                    if let pending = try await repository.task(taskID),
                        pending.attemptID == attemptID, pending.nativeID == nil,
                        pending.state == .queued, enqueuingAttempts.contains(attemptID)
                    {
                        // A terminal callback may beat the native-ID commit. Keep the event if
                        // its disk journal could not be written, and hold the background drain.
                        pendingEarlyFailures[attemptID] = event
                    }
                    return true
                }
                guard try await change(task, state: .transferFailed(reason: reason, resume: resume))
                else { return false }
                pendingEarlyFailures.removeValue(forKey: attemptID)
                try? await transfer.discardTerminalFailure(taskID: taskID, attemptID: attemptID)
                if resume == nil {
                    try? await transfer.discardResumeData(taskID: taskID, attemptID: attemptID)
                }
            case .drain(let identifier, let token):
                try await reconcile()
                if !pendingEarlyFailures.isEmpty { return false }
                for task in try await repository.all() {
                    if case .publishing = task.state { return false }
                    if task.state.isTransferActive,
                        try await transfer.stagedFile(
                            taskID: task.id, attemptID: task.attemptID) != nil
                    {
                        return false
                    }
                }
                await transfer.acknowledgeDrain(identifier: identifier, token: token)
            }
            return true
        } catch {
            // The event loop retries failed persistence before acknowledging a background drain.
            return false
        }
    }

    public func reconcile() async throws {
        if eventTask == nil {
            let events = await transfer.events()
            eventTask = Task { [weak self] in
                for await event in events {
                    while !Task.isCancelled {
                        guard let self else { return }
                        if await self.receive(event) { break }
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            }
        }
        let tasks = try await repository.all()
        let native = try await transfer.snapshot()
        let nativeByAttempt = Dictionary(grouping: native, by: \.attemptID)
        for task in tasks {
            if case .completed(let file) = task.state {
                pendingEarlyFailures.removeValue(forKey: task.attemptID)
                try? await transfer.discardResumeData(
                    taskID: task.id, attemptID: task.attemptID)
                try? await transfer.discardTerminalFailure(
                    taskID: task.id, attemptID: task.attemptID)
                if !(await publisher.exists(file)) {
                    _ = try await change(task, state: .missingFile(file), nativeID: nil)
                } else {
                    let staged = StagedFile(
                        taskID: task.id, attemptID: task.attemptID,
                        relativePath: "\(task.id.uuidString)/\(task.attemptID.uuidString).mp4")
                    // Cleanup is retried after launch if a previous completed commit outlived its file effect.
                    try? await publisher.cleanup(staged)
                }
                continue
            }
            if case .missingFile(let file) = task.state {
                if await publisher.exists(file) {
                    _ = try await change(task, state: .completed(file), nativeID: nil)
                }
                continue
            }
            if case .publishing(let staged) = task.state {
                pendingEarlyFailures.removeValue(forKey: task.attemptID)
                await publish(staged, for: task)
                continue
            }
            if case .cancelled = task.state {
                for nativeTask in nativeByAttempt[task.attemptID, default: []]
                where nativeTask.taskID == task.id {
                    try? await transfer.cancel(nativeTask.id)
                }
                continue
            }
            if enqueuingAttempts.contains(task.attemptID) { continue }
            if case .queued = task.state, reservingBatches > 0 { continue }
            guard task.state.isTransferActive || task.state.isPausedOrFailed else { continue }
            if try await recoverStaged(taskID: task.id, attemptID: task.attemptID) { continue }
            if try await recoverTerminalFailure(
                taskID: task.id, attemptID: task.attemptID,
                allowUnbound: nativeByAttempt[task.attemptID, default: []].isEmpty)
            {
                continue
            }
            // A paused or failed attempt can accept durable staged bytes, but an old system task
            // must not silently turn it back into a running transfer.
            if task.state.isPausedOrFailed { continue }
            if pausingAttempts.contains(task.attemptID) { continue }
            let matches = nativeByAttempt[task.attemptID, default: []].filter {
                $0.taskID == task.id
            }
            if let found = matches.first(where: { $0.id == task.nativeID }) ?? matches.first {
                let target: DownloadState
                switch found.state {
                case .running:
                    if case .transferring = task.state, task.nativeID == found.id {
                        target = task.state
                    } else {
                        target = .transferring(received: 0, total: nil)
                    }
                case .suspended: target = .interrupted(reason: "System transfer suspended")
                case .completed: target = .interrupted(reason: "Staged callback pending")
                }
                if task.nativeID != found.id || task.state != target {
                    // Recovery attaches only the same durable attempt; it never enqueues a second task.
                    _ = try await change(task, state: target, nativeID: found.id)
                }
            } else if case .transferring = task.state {
                _ = try await change(
                    task, state: .interrupted(reason: "System transfer missing"),
                    nativeID: task.nativeID)
            } else if case .queued = task.state, reservingBatches == 0,
                !enqueuingAttempts.contains(task.attemptID)
            {
                _ = try await change(
                    task, state: .interrupted(reason: "Enqueue outcome unknown"), nativeID: nil)
            } else if case .interrupted = task.state, task.nativeID != nil {
                _ = try await change(
                    task, state: .interrupted(reason: "System transfer missing"), nativeID: nil)
            }
        }
        let known = Set(tasks.map(\.attemptID))
        for orphan in native where !known.contains(orphan.attemptID) {
            if let current = try await repository.task(orphan.taskID),
                current.attemptID == orphan.attemptID
            {
                continue
            }
            try? await transfer.cancel(orphan.id)
        }
        for staged in try await transfer.stagedFiles() {
            let current = try await repository.task(staged.taskID)
            let isCurrent = current?.attemptID == staged.attemptID
            let isCancelled: Bool
            if case .cancelled = current?.state { isCancelled = true } else { isCancelled = false }
            if !isCurrent || isCancelled {
                // Obsolete callbacks can arrive after cancellation or attempt replacement.
                try? await publisher.cleanup(staged)
            }
        }
        let latestTasks = try await repository.all()
        var retainedResumeAttempts = enqueuingAttempts.union(pausingAttempts)
        for task in latestTasks {
            switch task.state {
            case .paused(let reference) where reference != nil,
                .transferFailed(_, let reference) where reference != nil:
                retainedResumeAttempts.insert(task.attemptID)
            default: break
            }
        }
        try await transfer.pruneResumeData(keepingAttempts: retainedResumeAttempts)
        await publish()
    }

    private func perform(_ action: DownloadAction, task: DownloadTask) async throws -> Bool {
        switch action {
        case .pause:
            guard let id = task.nativeID else { return false }
            guard pausingAttempts.insert(task.attemptID).inserted else { return false }
            defer { pausingAttempts.remove(task.attemptID) }
            guard
                try await change(task, state: .interrupted(reason: "Pause pending"), nativeID: id),
                let pending = try await repository.task(task.id),
                pending.attemptID == task.attemptID,
                pending.revision == task.revision + 1,
                pending.state == .interrupted(reason: "Pause pending")
            else { return false }
            do {
                let reference = try await transfer.pause(id)
                // Nil means the platform cannot resume; only restart is offered.
                let changed = try await change(
                    pending, state: .paused(resume: reference), nativeID: nil)
                if changed {
                    if reference == nil {
                        try? await transfer.discardResumeData(
                            taskID: task.id, attemptID: task.attemptID)
                    }
                    _ = try? await recoverStaged(taskID: task.id, attemptID: task.attemptID)
                }
                return changed
            } catch {
                _ = try? await change(
                    pending, state: .interrupted(reason: "Pause outcome unknown"), nativeID: id)
                throw DownloadFailure.transfer(error.localizedDescription)
            }
        case .resume:
            guard case .paused(let reference?) = task.state else { return false }
            guard enqueuingAttempts.insert(task.attemptID).inserted else { return false }
            defer { enqueuingAttempts.remove(task.attemptID) }
            guard try await change(task, state: .queued, nativeID: nil),
                let queued = try await repository.task(task.id),
                queued.attemptID == task.attemptID,
                queued.revision == task.revision + 1,
                queued.state == .queued
            else { return false }
            do {
                let nativeID = try await transfer.resume(queued, from: reference)
                do {
                    if try await !change(
                        queued, state: .transferring(received: 0, total: nil), nativeID: nativeID)
                    {
                        try? await transfer.cancel(nativeID)
                    } else if try await !recoverStaged(
                        taskID: task.id, attemptID: task.attemptID)
                    {
                        _ = try await recoverTerminalFailure(
                            taskID: task.id, attemptID: task.attemptID)
                    }
                } catch {
                    try? await transfer.cancel(nativeID)
                    throw error
                }
            } catch {
                _ = try await change(
                    queued, state: .interrupted(reason: error.localizedDescription), nativeID: nil)
                try? await reconcile()
            }
            return true
        case .retry:
            let fresh = task.replacing(attemptID: UUID(), state: .queued)
            enqueuingAttempts.insert(fresh.attemptID)
            defer { enqueuingAttempts.remove(fresh.attemptID) }
            guard
                try await repository.commit(
                    fresh, expectedRevision: task.revision, expectedAttempt: task.attemptID)
            else { return false }
            pendingEarlyFailures.removeValue(forKey: task.attemptID)
            try? await transfer.discardResumeData(taskID: task.id, attemptID: task.attemptID)
            try? await transfer.discardTerminalFailure(
                taskID: task.id, attemptID: task.attemptID)
            await publish()
            await enqueue(fresh)
            return true
        case .retryPublication:
            guard case .publicationFailed(_, let staged) = task.state else { return false }
            guard try await change(task, state: .publishing(staged), nativeID: nil),
                let publishing = try await repository.task(task.id)
            else { return false }
            await publish(staged, for: publishing)
            return true
        case .cancel:
            guard try await change(task, state: .cancelled, nativeID: nil) else { return false }
            pendingEarlyFailures.removeValue(forKey: task.attemptID)
            try? await transfer.discardResumeData(taskID: task.id, attemptID: task.attemptID)
            try? await transfer.discardTerminalFailure(
                taskID: task.id, attemptID: task.attemptID)
            if let id = task.nativeID { try? await transfer.cancel(id) }
            return true
        case .deleteFile:
            guard case .completed(let file) = task.state else { return false }
            try await publisher.delete(file)
            return try await change(task, state: .missingFile(file), nativeID: nil)
        case .removeRecord:
            let removed = try await repository.remove(
                task.id, expectedRevision: task.revision, expectedAttempt: task.attemptID)
            if removed {
                pendingEarlyFailures.removeValue(forKey: task.attemptID)
                try? await transfer.discardResumeData(
                    taskID: task.id, attemptID: task.attemptID)
                try? await transfer.discardTerminalFailure(
                    taskID: task.id, attemptID: task.attemptID)
                await publish()
            }
            return removed
        }
    }

    private func enqueue(_ task: DownloadTask) async {
        do {
            guard let current = try await repository.task(task.id),
                current.attemptID == task.attemptID,
                current.revision == task.revision,
                current.state == .queued
            else { return }
            let id = try await transfer.enqueue(task)
            do {
                if try await !change(
                    task, state: .transferring(received: 0, total: nil), nativeID: id)
                {
                    try? await transfer.cancel(id)
                } else {
                    if try await !recoverStaged(taskID: task.id, attemptID: task.attemptID) {
                        _ = try await recoverTerminalFailure(
                            taskID: task.id, attemptID: task.attemptID)
                    }
                }
            } catch {
                try? await transfer.cancel(id)
                throw error
            }
        } catch {
            // Enqueue may have reached URLSession before throwing. Reconciliation must inspect first.
            _ = try? await change(
                task, state: .interrupted(reason: error.localizedDescription), nativeID: nil)
            try? await reconcile()
        }
    }

    private func publish(_ staged: StagedFile, for task: DownloadTask) async {
        guard publishing.insert(task.id).inserted else { return }
        defer { publishing.remove(task.id) }
        do {
            guard let current = try await repository.task(task.id),
                current.attemptID == task.attemptID,
                current.revision == task.revision,
                current.state == .publishing(staged)
            else { return }
            let file = try await publisher.publish(staged, for: task)
            if try await change(task, state: .completed(file), nativeID: nil) {
                // Failed cleanup leaves a recoverable staging pointer for reconciliation.
                try? await publisher.cleanup(staged)
            }
        } catch let error as DownloadFileError {
            switch error {
            case .emptyFile, .invalidMedia:
                // These bytes can never publish successfully. A fresh transfer is the recovery.
                if (try? await change(
                    task, state: .transferFailed(reason: error.localizedDescription, resume: nil),
                    nativeID: nil)) == true
                {
                    try? await publisher.cleanup(staged)
                }
            default:
                _ = try? await change(
                    task,
                    state: .publicationFailed(reason: error.localizedDescription, staged: staged),
                    nativeID: nil)
            }
        } catch {
            _ = try? await change(
                task,
                state: .publicationFailed(reason: error.localizedDescription, staged: staged),
                nativeID: nil)
        }
    }

    private func recoverStaged(taskID: UUID, attemptID: UUID) async throws -> Bool {
        guard let staged = try await transfer.stagedFile(taskID: taskID, attemptID: attemptID),
            let task = try await repository.task(taskID), task.attemptID == attemptID,
            task.state.isTransferActive || task.state.isPausedOrFailed,
            try await change(task, state: .publishing(staged), nativeID: nil),
            let publishingTask = try await repository.task(taskID)
        else { return false }
        pendingEarlyFailures.removeValue(forKey: attemptID)
        try? await transfer.discardResumeData(taskID: taskID, attemptID: attemptID)
        try? await transfer.discardTerminalFailure(taskID: taskID, attemptID: attemptID)
        await publish(staged, for: publishingTask)
        return true
    }

    private func recoverTerminalFailure(
        taskID: UUID, attemptID: UUID, allowUnbound: Bool = false
    ) async throws -> Bool {
        if let pending = pendingEarlyFailures[attemptID],
            case .failed(_, _, let pendingNativeID, let reason, let resume) = pending,
            let task = try await repository.task(taskID), task.attemptID == attemptID
        {
            if task.nativeID == pendingNativeID {
                return await receive(pending)
            }
            if task.nativeID == nil, allowUnbound,
                !enqueuingAttempts.contains(attemptID), !pausingAttempts.contains(attemptID)
            {
                switch task.state {
                case .queued, .interrupted:
                    if try await change(
                        task, state: .transferFailed(reason: reason, resume: resume))
                    {
                        pendingEarlyFailures.removeValue(forKey: attemptID)
                        return true
                    }
                default: break
                }
            }
            if task.nativeID != nil {
                pendingEarlyFailures.removeValue(forKey: attemptID)
            }
        }
        guard let event = try await transfer.terminalFailure(taskID: taskID, attemptID: attemptID),
            case .failed(_, _, let nativeID, _, _) = event,
            let task = try await repository.task(taskID), task.attemptID == attemptID
        else { return false }
        if task.nativeID == nil, allowUnbound,
            !enqueuingAttempts.contains(attemptID), !pausingAttempts.contains(attemptID)
        {
            switch task.state {
            case .queued, .interrupted:
                if case .failed(_, _, _, let reason, let resume) = event,
                    try await change(
                        task, state: .transferFailed(reason: reason, resume: resume))
                {
                    pendingEarlyFailures.removeValue(forKey: attemptID)
                    try? await transfer.discardTerminalFailure(
                        taskID: taskID, attemptID: attemptID)
                    if resume == nil {
                        try? await transfer.discardResumeData(
                            taskID: taskID, attemptID: attemptID)
                    }
                    return true
                }
            default: break
            }
        }
        guard task.nativeID == nativeID else {
            if task.nativeID != nil {
                try? await transfer.discardTerminalFailure(
                    taskID: taskID, attemptID: attemptID)
            }
            return false
        }
        return await receive(event)
    }

    private func current(_ id: UUID, _ attempt: UUID, _ native: NativeTransferID) async throws
        -> DownloadTask?
    {
        guard let task = try await repository.task(id), task.attemptID == attempt,
            task.nativeID == native
        else { return nil }
        return task
    }

    private func change(
        _ task: DownloadTask, state: DownloadState, nativeID: NativeTransferID? = nil
    ) async throws -> Bool {
        let replacement = task.replacing(nativeID: nativeID, state: state)
        let committed = try await repository.commit(
            replacement, expectedRevision: task.revision, expectedAttempt: task.attemptID)
        if committed { await publish() }
        return committed
    }

    private func publish() async {
        publicationGeneration &+= 1
        let generation = publicationGeneration
        guard let tasks = try? await repository.all() else { return }
        guard generation == publicationGeneration else { return }
        snapshotRevision &+= 1
        let snapshot = DownloadSnapshot(revision: snapshotRevision, tasks: tasks)
        for continuation in observers.values { continuation.yield(snapshot) }
    }

    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}

extension DownloadState {
    fileprivate var isPausedOrFailed: Bool {
        switch self {
        case .paused, .transferFailed: true
        default: false
        }
    }
}
