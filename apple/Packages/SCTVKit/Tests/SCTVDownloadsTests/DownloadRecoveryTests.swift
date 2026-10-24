import Foundation
import GRDB
import SCTVCore
import Testing

@testable import SCTVData
@testable import SCTVDownloads

struct DownloadRecoveryTests {
    @Test func ambiguousEnqueueDoesNotDuplicate() async throws {
        let fixture = try Fixture()
        await fixture.driver.setAmbiguous(true)
        let result = await fixture.service.start([try fixture.request()])
        let taskID = try #require(result.accepted.first)
        #expect(await fixture.driver.enqueues == 1)
        try await fixture.service.reconcile()
        #expect(await fixture.driver.enqueues == 1)
        let task = try #require(await fixture.repository.task(taskID))
        #expect(task.state.isTransferActive)
    }

    @Test func retryAfterAmbiguousEnqueueFindsOriginalTransfer() async throws {
        let fixture = try Fixture()
        await fixture.driver.setAmbiguous(true)
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        let result = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: task.attemptID, action: .retry)
        ])
        #expect(result.accepted.isEmpty)
        #expect(await fixture.driver.enqueues == 1)
        #expect((try await fixture.repository.task(taskID))?.nativeID != nil)
    }

    @Test func cancelAfterAmbiguousEnqueueCancelsOriginalTransfer() async throws {
        let fixture = try Fixture()
        await fixture.driver.setAmbiguous(true)
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        let result = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: task.attemptID, action: .cancel)
        ])
        #expect(result.accepted == [taskID])
        #expect(try await fixture.driver.snapshot().isEmpty)
    }

    @Test func progressDuringPauseCannotLeaveNativeTaskUntracked() async throws {
        let fixture = try Fixture()
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        await fixture.driver.beforePause { nativeID in
            await fixture.service.receive(
                .progress(
                    taskID: taskID, attemptID: task.attemptID, nativeID: nativeID, received: 50,
                    total: 100))
        }
        let result = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: task.attemptID, action: .pause)
        ])
        #expect(result.accepted == [taskID])
        #expect(
            (try await fixture.repository.task(taskID))?.state
                == .paused(resume: .init(relativePath: "resume/fixture")))
    }

    @Test func reconciliationCannotInterruptTransferStartedDuringSnapshot() async throws {
        let fixture = try Fixture()
        let request = try fixture.request()
        await fixture.driver.beforeSnapshot {
            _ = await fixture.service.start([request])
        }
        try await fixture.service.reconcile()
        let task = try #require((try await fixture.repository.all()).first)
        #expect(task.state.isTransferActive)
        #expect(task.nativeID != nil)
        #expect(try await fixture.driver.snapshot().contains { $0.id == task.nativeID })
    }

    @Test func cancelDuringResumeSnapshotCannotResurrectTask() async throws {
        let fixture = try Fixture()
        let repository = HookedDownloadRepository(base: fixture.repository)
        let service = DownloadCoordinator(
            repository: repository, transfer: fixture.driver, publisher: FixturePublisher())
        let taskID = try #require((await service.start([try fixture.request()])).accepted.first)
        let transferring = try #require(await fixture.repository.task(taskID))
        _ = await service.perform([
            .init(taskID: taskID, expectedAttempt: transferring.attemptID, action: .pause)
        ])
        let paused = try #require(await fixture.repository.task(taskID))
        await repository.onNextAll { _ in
            if let queued = try? await fixture.repository.task(taskID), queued.state == .queued {
                _ = try? await fixture.repository.commit(
                    queued.replacing(state: .cancelled), expectedRevision: queued.revision,
                    expectedAttempt: queued.attemptID)
            }
        }
        _ = await service.perform([
            .init(taskID: taskID, expectedAttempt: paused.attemptID, action: .resume)
        ])
        #expect((try await fixture.repository.task(taskID))?.state == .cancelled)
        #expect(await fixture.driver.enqueues == 1)
    }

    @Test func cancelDuringAmbiguousEnqueueFindsNativeTransfer() async throws {
        let fixture = try Fixture()
        await fixture.driver.setAmbiguous(true)
        await fixture.driver.beforeReturn { task in
            _ = await fixture.service.perform([
                .init(taskID: task.id, expectedAttempt: task.attemptID, action: .cancel)
            ])
        }
        _ = await fixture.service.start([try fixture.request()])
        #expect((try await fixture.repository.all()).first?.state == .cancelled)
        #expect(try await fixture.driver.snapshot().isEmpty)
    }

    @Test func reconciliationPreservesTransferCreatedAfterDatabaseRead() async throws {
        let fixture = try Fixture()
        let repository = HookedDownloadRepository(base: fixture.repository)
        let service = DownloadCoordinator(
            repository: repository, transfer: fixture.driver, publisher: FixturePublisher())
        let request = try fixture.request()
        await repository.onNextAll { _ in
            _ = await service.start([request])
        }
        try await service.reconcile()
        let task = try #require((try await fixture.repository.all()).first)
        #expect(task.nativeID != nil)
        #expect(try await fixture.driver.snapshot().contains { $0.id == task.nativeID })
    }

    @Test func reconciliationDuringEnqueueDoesNotCancelAcceptedNativeTask() async throws {
        let fixture = try Fixture()
        await fixture.driver.beforeReturn { _ in
            try? await fixture.service.reconcile()
        }
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        #expect(task.nativeID != nil)
        #expect(try await fixture.driver.snapshot().contains { $0.id == task.nativeID })
    }

    @Test func reconciliationCannotPublishSameStagingTwice() async throws {
        let fixture = try Fixture()
        let publisher = ReentrantPublisher()
        let service = DownloadCoordinator(
            repository: fixture.repository, transfer: fixture.driver, publisher: publisher)
        let taskID = try #require((await service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        await publisher.onFirstPublish { try? await service.reconcile() }
        await service.receive(
            .staged(
                .init(
                    taskID: taskID, attemptID: task.attemptID,
                    relativePath: "\(taskID)/\(task.attemptID).mp4"),
                nativeID: try #require(task.nativeID)))
        #expect(await publisher.publishCount == 1)
        if case .completed = try await fixture.repository.task(taskID)?.state {
        } else {
            Issue.record("The staged task was not completed")
        }
    }

    @Test func slowOlderSnapshotCannotReplaceNewerSnapshot() async throws {
        let fixture = try Fixture()
        let repository = HookedDownloadRepository(base: fixture.repository)
        let service = DownloadCoordinator(
            repository: repository, transfer: fixture.driver, publisher: FixturePublisher())
        let stream = await service.updates()
        let recorder = SnapshotRecorder()
        let observer = Task {
            for await snapshot in stream { await recorder.record(snapshot.tasks.count) }
        }
        defer { observer.cancel() }
        let second = try fixture.request(contentID: "2")
        await repository.onNextAll { _ in
            _ = await service.start([second])
        }
        await fixture.driver.beforeReturn { task in
            if task.content.contentID == "1" { try? await Task.sleep(for: .milliseconds(50)) }
        }
        _ = await service.start([try fixture.request(contentID: "1")])
        let counts = await recorder.counts
        let firstTwo = try #require(counts.firstIndex(of: 2))
        #expect(!counts.dropFirst(firstTwo + 1).contains(1))
    }

    @Test func earlyStagedCallbackRecoversAfterNativeCorrelationCommit() async throws {
        let fixture = try Fixture()
        await fixture.driver.beforeReturn { task in
            let staged = StagedFile(
                taskID: task.id, attemptID: task.attemptID,
                relativePath: "\(task.id)/\(task.attemptID).mp4")
            await fixture.driver.storeStaged(staged)
            await fixture.service.receive(
                .staged(staged, nativeID: .init(session: "fixture", task: 1)))
        }
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        if case .completed = try await fixture.repository.task(taskID)?.state {
        } else {
            Issue.record("The early callback was not recovered from staging")
        }
    }

    @Test func stagingCleanupFollowsCompletedCommit() async throws {
        let fixture = try Fixture()
        let publisher = RecordingPublisher(repository: fixture.repository)
        let service = DownloadCoordinator(
            repository: fixture.repository, transfer: fixture.driver, publisher: publisher)
        let taskID = try #require((await service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        let staged = StagedFile(
            taskID: taskID, attemptID: task.attemptID,
            relativePath: "\(taskID)/\(task.attemptID).mp4")
        await service.receive(.staged(staged, nativeID: try #require(task.nativeID)))
        #expect(await publisher.cleanupSawCompleted)
        #expect(
            (try await fixture.repository.task(taskID))?.state
                == .completed(
                    .init(
                        destination: .applicationManaged, relativeFilename: "Clip.mp4", byteSize: 1,
                        fileIdentity: "fixture")))
    }

    @Test func reconciliationKeepsCurrentNativeIDWhenOldTaskRemains() async throws {
        let fixture = try Fixture()
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        let current = try #require(task.nativeID)
        await fixture.driver.prepend(
            .init(
                id: .init(session: "fixture", task: 999), taskID: taskID, attemptID: task.attemptID,
                state: .suspended))
        try await fixture.service.reconcile()
        #expect((try await fixture.repository.task(taskID))?.nativeID == current)
    }

    @Test func cancelledReservationDoesNotLeaveNativeTransfer() async throws {
        let fixture = try Fixture()
        await fixture.driver.beforeReturn { task in
            _ = try? await fixture.repository.commit(
                task.replacing(state: .cancelled), expectedRevision: task.revision,
                expectedAttempt: task.attemptID)
        }
        _ = await fixture.service.start([try fixture.request()])
        #expect((try await fixture.repository.all()).first?.state == .cancelled)
        #expect(try await fixture.driver.snapshot().isEmpty)
    }
}

actor RecordingPublisher: FilePublisher {
    let repository: SQLiteDownloadRepository
    var cleanupSawCompleted = false

    init(repository: SQLiteDownloadRepository) { self.repository = repository }

    func publish(_ staged: StagedFile, for task: DownloadTask) async throws -> PublishedFile {
        .init(
            destination: task.destination, relativeFilename: task.filename, byteSize: 1,
            fileIdentity: "fixture")
    }

    func cleanup(_ staged: StagedFile) async throws {
        if case .completed = try await repository.task(staged.taskID)?.state {
            cleanupSawCompleted = true
        }
    }

    func delete(_ file: PublishedFile) async throws {}
    func exists(_ file: PublishedFile) async -> Bool { true }
}

actor ReentrantPublisher: FilePublisher {
    var publishCount = 0
    private var firstPublishHook: (@Sendable () async -> Void)?

    func onFirstPublish(_ hook: @escaping @Sendable () async -> Void) { firstPublishHook = hook }
    func publish(_ staged: StagedFile, for task: DownloadTask) async throws -> PublishedFile {
        publishCount += 1
        if let hook = firstPublishHook {
            firstPublishHook = nil
            await hook()
        }
        return .init(
            destination: task.destination, relativeFilename: task.filename, byteSize: 1,
            fileIdentity: "fixture")
    }
    func delete(_ file: PublishedFile) async throws {}
    func exists(_ file: PublishedFile) async -> Bool { true }
}

actor SnapshotRecorder {
    var counts: [Int] = []
    func record(_ count: Int) { counts.append(count) }
}

actor HookedDownloadRepository: DownloadRepository {
    let base: SQLiteDownloadRepository
    private var nextAllHook: (@Sendable ([DownloadTask]) async -> Void)?

    init(base: SQLiteDownloadRepository) { self.base = base }
    func onNextAll(_ hook: @escaping @Sendable ([DownloadTask]) async -> Void) {
        nextAllHook = hook
    }
    func reserve(_ request: DownloadRequest) async throws -> DownloadTask {
        try await base.reserve(request)
    }
    func commit(_ task: DownloadTask, expectedRevision: UInt64, expectedAttempt: UUID) async throws
        -> Bool
    {
        try await base.commit(
            task, expectedRevision: expectedRevision, expectedAttempt: expectedAttempt)
    }
    func task(_ id: UUID) async throws -> DownloadTask? { try await base.task(id) }
    func all() async throws -> [DownloadTask] {
        let values = try await base.all()
        if let hook = nextAllHook {
            nextAllHook = nil
            await hook(values)
        }
        return values
    }
    func remove(_ id: UUID, expectedRevision: UInt64, expectedAttempt: UUID) async throws -> Bool {
        try await base.remove(
            id, expectedRevision: expectedRevision, expectedAttempt: expectedAttempt)
    }
}

actor FixtureDriver: TransferDriver {
    var enqueues = 0
    private var ambiguous = false
    private var transfers: [NativeTransfer] = []
    private var enqueueHook: (@Sendable (DownloadTask) async -> Void)?
    private var pauseHook: (@Sendable (NativeTransferID) async -> Void)?
    private var snapshotHook: (@Sendable () async -> Void)?
    private var stagedFiles: [UUID: StagedFile] = [:]
    private var failures: [UUID: TransferEvent] = [:]

    func setAmbiguous(_ value: Bool) { ambiguous = value }
    func prepend(_ transfer: NativeTransfer) { transfers.insert(transfer, at: 0) }
    func beforeReturn(_ hook: @escaping @Sendable (DownloadTask) async -> Void) {
        enqueueHook = hook
    }
    func beforePause(_ hook: @escaping @Sendable (NativeTransferID) async -> Void) {
        pauseHook = hook
    }
    func beforeSnapshot(_ hook: @escaping @Sendable () async -> Void) { snapshotHook = hook }
    func storeStaged(_ file: StagedFile) { stagedFiles[file.attemptID] = file }
    func storeFailure(_ event: TransferEvent) {
        if case .failed(_, let attemptID, _, _, _) = event { failures[attemptID] = event }
    }
    func terminalFailure(taskID: UUID, attemptID: UUID) async throws -> TransferEvent? {
        guard let event = failures[attemptID] else { return nil }
        if case .failed(let storedTaskID, _, _, _, _) = event, storedTaskID == taskID {
            return event
        }
        return nil
    }
    func stagedFile(taskID: UUID, attemptID: UUID) async throws -> StagedFile? {
        stagedFiles[attemptID].flatMap { $0.taskID == taskID ? $0 : nil }
    }
    func stagedFiles() async throws -> [StagedFile] { Array(stagedFiles.values) }
    func enqueue(_ task: DownloadTask) async throws -> NativeTransferID {
        enqueues += 1
        let id = NativeTransferID(session: "fixture", task: enqueues)
        transfers.append(.init(id: id, taskID: task.id, attemptID: task.attemptID, state: .running))
        if let enqueueHook { await enqueueHook(task) }
        if ambiguous { throw NSError(domain: "fixture", code: 1) }
        return id
    }
    func cancel(_ id: NativeTransferID) async throws { transfers.removeAll { $0.id == id } }
    func pause(_ id: NativeTransferID) async throws -> ResumeReference? {
        if let pauseHook { await pauseHook(id) }
        transfers.removeAll { $0.id == id }
        return .init(relativePath: "resume/fixture")
    }
    func resume(_ task: DownloadTask, from reference: ResumeReference) async throws
        -> NativeTransferID
    { try await enqueue(task) }
    func snapshot() async throws -> [NativeTransfer] {
        let current = transfers
        if let hook = snapshotHook {
            snapshotHook = nil
            await hook()
        }
        return current
    }
    func events() async -> AsyncStream<TransferEvent> { AsyncStream { _ in } }
}

struct FixturePublisher: FilePublisher {
    func publish(_ staged: StagedFile, for task: DownloadTask) async throws -> PublishedFile {
        .init(
            destination: task.destination, relativeFilename: task.filename, byteSize: 1,
            fileIdentity: "fixture")
    }
    func delete(_ file: PublishedFile) async throws {}
    func exists(_ file: PublishedFile) async -> Bool { true }
}

struct Fixture: Sendable {
    let repository: SQLiteDownloadRepository
    let driver = FixtureDriver()
    let service: DownloadCoordinator

    init() throws {
        let database = try DatabaseQueue()
        try RuntimeMigrations.migrator.migrate(database)
        repository = SQLiteDownloadRepository(database: database)
        service = DownloadCoordinator(
            repository: repository, transfer: driver, publisher: FixturePublisher())
    }

    func request(contentID: String = "7") throws -> DownloadRequest {
        let ref = try ContentRef(programmeID: "1", dateID: "2", contentID: contentID)
        let source = try MediaSource(
            url: URL(string: "https://fscgc.scgchc.com/a.mp4")!, quality: .standard)
        return DownloadRequest(
            content: ref, programmeName: "News", broadcastDate: "2026-10-16", title: "Clip",
            cover: nil, source: source, filename: "Clip.mp4", allowsCellular: false,
            destination: .applicationManaged)
    }
}
