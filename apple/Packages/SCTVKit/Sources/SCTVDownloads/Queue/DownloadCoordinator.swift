import Foundation
import OSLog
import SCTVCore

/// Serializes durable download transitions and owns native event consumption.
public actor DownloadCoordinator: DownloadService {
    private struct DownloadIdentity: Hashable {
        let content: ContentRef
        let quality: VideoQuality

        init(_ request: DownloadRequest) {
            content = request.content
            quality = request.source.quality
        }
    }

    private struct TerminalFailure: Sendable {
        let taskID: UUID
        let attemptID: UUID
        let nativeID: NativeTransferID
        let reason: String
        let resume: ResumeReference?

        init?(_ event: TransferEvent) {
            guard
                case .failed(let taskID, let attemptID, let nativeID, let reason, let resume) =
                    event
            else { return nil }
            self.taskID = taskID
            self.attemptID = attemptID
            self.nativeID = nativeID
            self.reason = reason
            self.resume = resume
        }
    }

    private static let batchLimit = 100
    private static let logger = Logger(subsystem: "dev.sctvdl.apple", category: "download-queue")

    private let repository: any DownloadRepository
    private let transfer: any TransferDriver
    private let publisher: any FilePublisher

    private var eventSubscription: Task<AsyncStream<TransferEvent>, Never>?
    private var eventTask: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<DownloadSnapshot>.Continuation] = [:]
    private var snapshotRevision: UInt64 = 0
    private var snapshotLoadGeneration: UInt64 = 0

    private var publishing: Set<UUID> = []
    private var fileClaims: Set<UUID> = []
    private var reservingBatches = 0
    private var enqueuingAttempts: Set<UUID> = []
    private var pendingEarlyFailures: [UUID: TerminalFailure] = [:]
    private var pausingAttempts: Set<UUID> = []

    public init(
        repository: any DownloadRepository, transfer: any TransferDriver,
        publisher: any FilePublisher
    ) {
        self.repository = repository
        self.transfer = transfer
        self.publisher = publisher
    }

    deinit {
        eventSubscription?.cancel()
        eventTask?.cancel()
    }

    public func start(_ requests: [DownloadRequest]) async -> DownloadBatchResult {
        let identities = Set(requests.map(DownloadIdentity.init))
        guard identities.count <= Self.batchLimit else {
            return .init(
                accepted: [],
                failures: requests.map { .init(content: $0.content, reason: .batchTooLarge) })
        }

        reservingBatches += 1
        defer { reservingBatches -= 1 }

        var accepted: [UUID] = []
        var acceptedContent: [ContentRef] = []
        var failures: [DownloadItemFailure] = []
        var seen: Set<DownloadIdentity> = []

        for request in requests {
            guard seen.insert(DownloadIdentity(request)).inserted else {
                failures.append(.init(content: request.content, reason: .duplicate))
                continue
            }

            do {
                let reserved = try await repository.reserve(request)
                accepted.append(reserved.id)
                acceptedContent.append(reserved.content)

                enqueuingAttempts.insert(reserved.attemptID)
                await broadcastSnapshot()
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

        return .init(accepted: accepted, failures: failures, acceptedContent: acceptedContent)
    }

    public func perform(_ commands: [DownloadCommand]) async -> DownloadBatchResult {
        guard Set(commands.map(\.taskID)).count <= Self.batchLimit else {
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
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }

        await broadcastSnapshot()
        return stream
    }

    @discardableResult
    public func receive(_ event: TransferEvent) async -> Bool {
        do {
            switch event {
            case .progress(let taskID, let attemptID, let nativeID, let received, let total):
                let state = DownloadState.transferring(received: received, total: total)
                try await recordProgress(
                    state, identity: (taskID: taskID, attemptID: attemptID, nativeID: nativeID))
            case .staged(let staged, let nativeID):
                try await receiveStagedFile(staged, from: nativeID)
            case .failed:
                guard let failure = TerminalFailure(event) else { return true }
                return try await receiveTerminalFailure(failure)
            case .drain(let identifier, let token):
                return try await completeDrain(identifier: identifier, token: token)
            }
            return true
        } catch {
            // The event loop retries failed persistence before acknowledging a background drain.
            return false
        }
    }

    private func recordProgress(
        _ state: DownloadState,
        identity: (taskID: UUID, attemptID: UUID, nativeID: NativeTransferID)
    ) async throws {
        guard case .transferring(let received, _) = state, received >= 0,
            let task = try await repository.task(identity.taskID),
            task.attemptID == identity.attemptID, task.nativeID == identity.nativeID,
            case .transferring = task.state
        else { return }

        _ = try await commitState(task, state: state, nativeID: identity.nativeID)
    }

    private func receiveStagedFile(_ staged: StagedFile, from nativeID: NativeTransferID)
        async throws
    {
        guard let task = try await repository.task(staged.taskID),
            task.attemptID == staged.attemptID, task.state != .cancelled
        else {
            // A cancelled or replaced attempt may still deliver its temporary file.
            try? await publisher.cleanup(staged)
            return
        }

        guard task.nativeID == nativeID else {
            // Staging is durable even if the callback beat the native-ID commit.
            _ = try await recoverStaged(taskID: staged.taskID, attemptID: staged.attemptID)
            return
        }

        guard try await commitState(task, state: .publishing(staged)) else { return }
        pendingEarlyFailures.removeValue(forKey: staged.attemptID)
        await discardTransferArtifacts(task)
        if let publishing = try await repository.task(task.id) {
            await publishFile(staged, for: publishing)
        }
    }

    private func receiveTerminalFailure(_ failure: TerminalFailure) async throws -> Bool {
        guard let task = try await repository.task(failure.taskID),
            task.attemptID == failure.attemptID
        else { return true }

        if task.nativeID == failure.nativeID {
            return try await commitTerminalFailure(failure, for: task)
        }

        if task.nativeID == nil, task.state == .queued,
            enqueuingAttempts.contains(failure.attemptID)
        {
            // A terminal callback may beat native-ID persistence. Keep the live
            // event even if saving its disk receipt failed.
            pendingEarlyFailures[failure.attemptID] = failure
        }
        return true
    }

    private func completeDrain(identifier: String, token: UUID) async throws -> Bool {
        try await reconcile()
        guard pendingEarlyFailures.isEmpty else { return false }

        // Acknowledging the system while staged work is still recoverable can
        // suspend the process before its durable result is committed.
        for task in try await repository.all() {
            if case .publishing = task.state { return false }
            if task.state.isTransferActive,
                try await transfer.stagedFile(taskID: task.id, attemptID: task.attemptID) != nil
            {
                return false
            }
        }

        await transfer.acknowledgeDrain(identifier: identifier, token: token)
        return true
    }

    public func reconcile() async throws {
        await subscribeToTransferEventsIfNeeded()

        let tasks = try await repository.all()
        let native = try await transfer.snapshot()
        let nativeByAttempt = Dictionary(grouping: native, by: \.attemptID)
        for task in tasks {
            try await reconcile(task, nativeTransfers: nativeByAttempt[task.attemptID, default: []])
        }

        try await cancelOrphanedTransfers(native, knownAttempts: Set(tasks.map(\.attemptID)))
        try await cleanupObsoleteStaging()
        try await pruneUnreferencedResumeData()
        await broadcastSnapshot()
    }

    private func subscribeToTransferEventsIfNeeded() async {
        guard eventTask == nil else { return }

        // Opening the stream can suspend. Reserve one subscription first since opening
        // a second native stream replaces the previous callback consumer.
        let subscription = eventSubscription ?? Task { [transfer] in await transfer.events() }
        eventSubscription = subscription
        let events = await subscription.value
        guard eventTask == nil else { return }

        eventSubscription = nil
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

    private func reconcile(_ task: DownloadTask, nativeTransfers: [NativeTransfer]) async throws {
        if case .completed(let file) = task.state {
            try await reconcilePublishedFile(file, task: task)
            return
        }

        if case .missingFile(let file) = task.state {
            try await reconcilePublishedFile(file, task: task)
            return
        }

        if case .publishing(let staged) = task.state {
            pendingEarlyFailures.removeValue(forKey: task.attemptID)
            await publishFile(staged, for: task)
            return
        }
        if case .cancelled = task.state {
            for nativeTask in nativeTransfers
            where nativeTask.taskID == task.id {
                try? await transfer.cancel(nativeTask.id)
            }
            return
        }

        if enqueuingAttempts.contains(task.attemptID) { return }
        if case .queued = task.state, reservingBatches > 0 { return }
        guard task.state.isTransferActive || task.state.isPausedOrFailed else { return }

        if try await recoverStaged(taskID: task.id, attemptID: task.attemptID) { return }
        if try await recoverTerminalFailure(
            taskID: task.id, attemptID: task.attemptID,
            allowUnbound: nativeTransfers.isEmpty)
        {
            return
        }

        // A paused or failed attempt can accept durable staged bytes, but an old system task
        // must not silently turn it back into a running transfer.
        if task.state.isPausedOrFailed { return }
        if pausingAttempts.contains(task.attemptID) { return }

        let matches = nativeTransfers.filter {
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
                _ = try await commitState(task, state: target, nativeID: found.id)
            }
        } else if case .transferring = task.state {
            _ = try await commitState(
                task, state: .interrupted(reason: "System transfer missing"),
                nativeID: task.nativeID)
        } else if case .queued = task.state, reservingBatches == 0,
            !enqueuingAttempts.contains(task.attemptID)
        {
            _ = try await commitState(
                task, state: .interrupted(reason: "Enqueue outcome unknown"), nativeID: nil)
        } else if case .interrupted = task.state, task.nativeID != nil {
            _ = try await commitState(
                task, state: .interrupted(reason: "System transfer missing"), nativeID: nil)
        }
    }

    private func reconcilePublishedFile(_ file: PublishedFile, task: DownloadTask) async throws {
        guard fileClaims.insert(task.id).inserted else { return }
        defer { fileClaims.remove(task.id) }

        guard let current = try await repository.task(task.id),
            current.attemptID == task.attemptID, current.revision == task.revision
        else { return }

        let isPresent: Bool
        do {
            isPresent = try await publisher.exists(file)
        } catch {
            // A probe may fail while file protection is active or a scope is unavailable.
            // Leave the record alone and let later reconciles retry the inspection.
            Self.logger.warning(
                "Downloaded file inspection deferred: \(error.localizedDescription, privacy: .private)"
            )
            return
        }

        switch task.state {
        case .completed:
            pendingEarlyFailures.removeValue(forKey: task.attemptID)
            await discardTransferArtifacts(task)

            guard isPresent else {
                _ = try await commitState(task, state: .missingFile(file), nativeID: nil)
                return
            }

            // The completed write may have survived a crash before staging cleanup.
            let staged = StagedFile(
                taskID: task.id, attemptID: task.attemptID,
                relativePath: "\(task.id.uuidString)/\(task.attemptID.uuidString).mp4")
            try? await publisher.cleanup(staged)
        case .missingFile where isPresent:
            _ = try await commitState(task, state: .completed(file), nativeID: nil)
        default:
            break
        }
    }

    private func cancelOrphanedTransfers(
        _ native: [NativeTransfer], knownAttempts: Set<UUID>
    ) async throws {
        for orphan in native where !knownAttempts.contains(orphan.attemptID) {
            if let current = try await repository.task(orphan.taskID),
                current.attemptID == orphan.attemptID
            {
                continue
            }
            try? await transfer.cancel(orphan.id)
        }
    }

    private func cleanupObsoleteStaging() async throws {
        for staged in try await transfer.stagedFiles() {
            let current = try await repository.task(staged.taskID)
            let isCurrent = current?.attemptID == staged.attemptID
            let isCancelled = current?.state == .cancelled
            if !isCurrent || isCancelled {
                // Obsolete callbacks can arrive after cancellation or attempt replacement.
                try? await publisher.cleanup(staged)
            }
        }
    }

    private func pruneUnreferencedResumeData() async throws {
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
    }

    private func perform(_ action: DownloadAction, task: DownloadTask) async throws -> Bool {
        switch action {
        case .pause:
            return try await pause(task)
        case .resume:
            return try await resume(task)
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
            await broadcastSnapshot()
            await enqueue(fresh)
            return true
        case .retryPublication:
            guard case .publicationFailed(_, let staged) = task.state else { return false }
            guard try await commitState(task, state: .publishing(staged), nativeID: nil),
                let publishing = try await repository.task(task.id)
            else { return false }
            await publishFile(staged, for: publishing)
            return true
        case .cancel:
            guard try await commitState(task, state: .cancelled, nativeID: nil) else {
                return false
            }
            pendingEarlyFailures.removeValue(forKey: task.attemptID)
            try? await transfer.discardResumeData(taskID: task.id, attemptID: task.attemptID)
            try? await transfer.discardTerminalFailure(
                taskID: task.id, attemptID: task.attemptID)
            if let id = task.nativeID { try? await transfer.cancel(id) }
            return true
        case .deleteFile, .removeRecord:
            return try await performFileCommand(action, task: task)
        }
    }

    private func performFileCommand(_ action: DownloadAction, task: DownloadTask) async throws
        -> Bool
    {
        // Deleting bytes is irreversible. Keep record removal and reconciliation
        // from overtaking it while the platform or repository is suspended.
        guard fileClaims.insert(task.id).inserted else { return false }
        defer { fileClaims.remove(task.id) }

        guard let latest = try await repository.task(task.id),
            latest.attemptID == task.attemptID, latest.revision == task.revision
        else { return false }

        switch action {
        case .deleteFile:
            guard case .completed(let file) = latest.state else { return false }
            try await publisher.delete(file)
            return try await commitState(latest, state: .missingFile(file), nativeID: nil)
        case .removeRecord:
            let removed = try await repository.remove(
                latest.id, expectedRevision: latest.revision, expectedAttempt: latest.attemptID)
            if removed {
                pendingEarlyFailures.removeValue(forKey: latest.attemptID)
                await discardTransferArtifacts(latest)
                await broadcastSnapshot()
            }
            return removed
        default:
            return false
        }
    }

    private func discardTransferArtifacts(_ task: DownloadTask) async {
        // A completed or obsolete attempt no longer depends on these resources.
        // Cleanup failure must not invalidate the durable task state.
        try? await transfer.discardResumeData(taskID: task.id, attemptID: task.attemptID)
        try? await transfer.discardTerminalFailure(taskID: task.id, attemptID: task.attemptID)
    }

    private func pause(_ task: DownloadTask) async throws -> Bool {
        guard let id = task.nativeID else { return false }
        guard pausingAttempts.insert(task.attemptID).inserted else { return false }
        defer { pausingAttempts.remove(task.attemptID) }

        guard
            try await commitState(task, state: .interrupted(reason: "Pause pending"), nativeID: id),
            let pending = try await repository.task(task.id),
            pending.attemptID == task.attemptID,
            pending.revision == task.revision + 1,
            pending.state == .interrupted(reason: "Pause pending")
        else { return false }

        do {
            let reference = try await transfer.pause(id)
            // Nil means the platform cannot resume; only restart is offered.
            let changed = try await commitState(
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
            _ = try? await commitState(
                pending, state: .interrupted(reason: "Pause outcome unknown"), nativeID: id)
            throw DownloadFailure.transfer(error.localizedDescription)
        }
    }

    private func resume(_ task: DownloadTask) async throws -> Bool {
        guard case .paused(let reference?) = task.state else { return false }
        guard enqueuingAttempts.insert(task.attemptID).inserted else { return false }
        defer { enqueuingAttempts.remove(task.attemptID) }

        guard try await commitState(task, state: .queued, nativeID: nil),
            let queued = try await repository.task(task.id),
            queued.attemptID == task.attemptID,
            queued.revision == task.revision + 1,
            queued.state == .queued
        else { return false }

        do {
            let nativeID = try await transfer.resume(queued, from: reference)
            try await attachNativeTransfer(nativeID, to: queued)
        } catch {
            _ = try await commitState(
                queued, state: .interrupted(reason: transferReason(error)), nativeID: nil)
            try? await reconcile()
        }
        return true
    }

    private func enqueue(_ task: DownloadTask) async {
        do {
            guard let current = try await repository.task(task.id),
                current.attemptID == task.attemptID,
                current.revision == task.revision,
                current.state == .queued
            else { return }

            let id = try await transfer.enqueue(task)
            try await attachNativeTransfer(id, to: task)
        } catch {
            // Enqueue may have reached URLSession before throwing. Reconciliation must inspect first.
            _ = try? await commitState(
                task, state: .interrupted(reason: transferReason(error)), nativeID: nil)
            try? await reconcile()
        }
    }

    private func transferReason(_ error: any Error) -> String {
        if let transferError = error as? BackgroundTransferError {
            return transferError.issueCode.rawValue
        }
        return error.localizedDescription
    }

    private func attachNativeTransfer(_ nativeID: NativeTransferID, to task: DownloadTask)
        async throws
    {
        do {
            guard
                try await commitState(
                    task, state: .transferring(received: 0, total: nil), nativeID: nativeID)
            else {
                try? await transfer.cancel(nativeID)
                return
            }

        } catch {
            // A native task with no durable identity cannot be tracked safely.
            try? await transfer.cancel(nativeID)
            throw error
        }

        do {
            // Callbacks may arrive before the native correlation is durable. Recover bytes first;
            // a terminal failure must not replace an already staged successful transfer.
            if try await !recoverStaged(taskID: task.id, attemptID: task.attemptID) {
                _ = try await recoverTerminalFailure(taskID: task.id, attemptID: task.attemptID)
            }
        } catch {
            // Its durable identity already owns the transfer. A journal read failure
            // is recoverable and must not cancel a running download.
            Self.logger.warning(
                "Recovery of an attached transfer was deferred: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private func publishFile(_ staged: StagedFile, for task: DownloadTask) async {
        guard publishing.insert(task.id).inserted else { return }
        defer { publishing.remove(task.id) }
        do {
            guard let current = try await repository.task(task.id),
                current.attemptID == task.attemptID,
                current.revision == task.revision,
                current.state == .publishing(staged)
            else { return }

            let file = try await publisher.publish(staged, for: task)
            if try await commitState(task, state: .completed(file), nativeID: nil) {
                // Failed cleanup leaves a recoverable staging pointer for reconciliation.
                try? await publisher.cleanup(staged)
            }
        } catch let error as DownloadFileError {
            switch error {
            case .emptyFile, .invalidMedia:
                // These bytes can never publish successfully. A fresh transfer is the recovery.
                if (try? await commitState(
                    task, state: .transferFailed(reason: error.issueCode.rawValue, resume: nil),
                    nativeID: nil)) == true
                {
                    try? await publisher.cleanup(staged)
                }
            default:
                _ = try? await commitState(
                    task,
                    state: .publicationFailed(reason: error.issueCode.rawValue, staged: staged),
                    nativeID: nil)
            }
        } catch {
            _ = try? await commitState(
                task,
                state: .publicationFailed(reason: error.localizedDescription, staged: staged),
                nativeID: nil)
        }
    }

    private func recoverStaged(taskID: UUID, attemptID: UUID) async throws -> Bool {
        guard let staged = try await transfer.stagedFile(taskID: taskID, attemptID: attemptID),
            let task = try await repository.task(taskID), task.attemptID == attemptID,
            task.state.isTransferActive || task.state.isPausedOrFailed,
            try await commitState(task, state: .publishing(staged), nativeID: nil),
            let publishingTask = try await repository.task(taskID)
        else { return false }

        pendingEarlyFailures.removeValue(forKey: attemptID)
        try? await transfer.discardResumeData(taskID: taskID, attemptID: attemptID)
        try? await transfer.discardTerminalFailure(taskID: taskID, attemptID: attemptID)
        await publishFile(staged, for: publishingTask)
        return true
    }

    private func recoverTerminalFailure(
        taskID: UUID, attemptID: UUID, allowUnbound: Bool = false
    ) async throws -> Bool {
        if let pending = pendingEarlyFailures[attemptID],
            let task = try await repository.task(taskID), task.attemptID == attemptID
        {
            if task.nativeID == pending.nativeID {
                return try await commitTerminalFailure(pending, for: task)
            }
            if canClaimUnboundFailure(task, allowUnbound: allowUnbound),
                try await commitTerminalFailure(pending, for: task)
            {
                return true
            }

            // A different native task now owns this attempt.
            if task.nativeID != nil {
                pendingEarlyFailures.removeValue(forKey: attemptID)
            }
        }

        guard let event = try await transfer.terminalFailure(taskID: taskID, attemptID: attemptID),
            let failure = TerminalFailure(event),
            let task = try await repository.task(taskID), task.attemptID == attemptID
        else { return false }

        if task.nativeID == failure.nativeID
            || canClaimUnboundFailure(task, allowUnbound: allowUnbound)
        {
            return try await commitTerminalFailure(failure, for: task)
        }

        if task.nativeID != nil {
            // Its journal belongs to an obsolete native task and cannot be applied.
            try? await transfer.discardTerminalFailure(taskID: taskID, attemptID: attemptID)
        }
        return false
    }

    private func canClaimUnboundFailure(_ task: DownloadTask, allowUnbound: Bool) -> Bool {
        guard allowUnbound, task.nativeID == nil,
            !enqueuingAttempts.contains(task.attemptID), !pausingAttempts.contains(task.attemptID)
        else { return false }

        switch task.state {
        case .queued, .interrupted: return true
        default: return false
        }
    }

    private func commitTerminalFailure(_ failure: TerminalFailure, for task: DownloadTask)
        async throws -> Bool
    {
        guard
            try await commitState(
                task, state: .transferFailed(reason: failure.reason, resume: failure.resume))
        else { return false }

        // Journal cleanup follows successful CAS so a failed write remains recoverable.
        pendingEarlyFailures.removeValue(forKey: failure.attemptID)
        try? await transfer.discardTerminalFailure(
            taskID: failure.taskID, attemptID: failure.attemptID)
        if failure.resume == nil {
            try? await transfer.discardResumeData(
                taskID: failure.taskID, attemptID: failure.attemptID)
        }
        return true
    }

    private func commitState(
        _ task: DownloadTask, state: DownloadState, nativeID: NativeTransferID? = nil
    ) async throws -> Bool {
        let replacement = task.replacing(nativeID: nativeID, state: state)

        let committed = try await repository.commit(
            replacement, expectedRevision: task.revision, expectedAttempt: task.attemptID)
        if committed { await broadcastSnapshot() }
        return committed
    }

    private func broadcastSnapshot() async {
        snapshotLoadGeneration &+= 1
        let generation = snapshotLoadGeneration
        guard let tasks = try? await repository.all() else { return }
        guard generation == snapshotLoadGeneration else { return }

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
