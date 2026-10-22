import Foundation
import SCTVCore
import Testing

@testable import SCTVDownloads

struct BackgroundTransferTests {
    @Test func policyChangeDoesNotRewriteExistingTask() async throws {
        let fixture = try Fixture()
        let original = try await fixture.repository.reserve(fixture.request())
        let newPreference = true

        #expect(!original.allowsCellular)
        #expect(
            BackgroundSessionDriver.identifier(allowsCellular: original.allowsCellular)
                == BackgroundSessionDriver.cellularDisallowedIdentifier)
        #expect(
            BackgroundSessionDriver.identifier(allowsCellular: newPreference)
                == BackgroundSessionDriver.cellularAllowedIdentifier)
        let originalConfiguration = BackgroundSessionDriver.configuration(allowsCellular: false)
        let newConfiguration = BackgroundSessionDriver.configuration(allowsCellular: true)
        #expect(
            originalConfiguration.identifier == BackgroundSessionDriver.cellularDisallowedIdentifier
        )
        #expect(!originalConfiguration.allowsCellularAccess)
        #expect(newConfiguration.allowsCellularAccess)
        let request = try BackgroundSessionDriver.request(for: original)
        #expect(request.value(forHTTPHeaderField: "Referer") != nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") != nil)
        #expect(request.allHTTPHeaderFields?.count == 2)
    }

    @Test func invalidResumeOffersRestart() async throws {
        let fixture = try Fixture()
        let task = try await fixture.repository.reserve(fixture.request())
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = try BackgroundSessionDriver(
            stagingRoot: root.appending(path: "Staging"),
            resumeRoot: root.appending(path: "Resume"))

        await #expect(throws: BackgroundTransferError.self) {
            try await driver.resume(task, from: ResumeReference(relativePath: "missing.resume"))
        }
        #expect(DownloadState.interrupted(reason: "Resume data invalid").allows(.retry))
    }

    @Test func unknownTotalRemainsUnknown() async throws {
        let fixture = try Fixture()
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        let nativeID = try #require(task.nativeID)

        await fixture.service.receive(
            .progress(
                taskID: task.id, attemptID: task.attemptID, nativeID: nativeID,
                received: 12, total: nil))

        #expect(
            (try await fixture.repository.task(taskID))?.state
                == .transferring(received: 12, total: nil))
    }

    @Test func replacedAttemptCallbackIsIgnored() async throws {
        let fixture = try Fixture()
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let original = try #require(await fixture.repository.task(taskID))
        _ = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: original.attemptID, action: .cancel)
        ])
        _ = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: original.attemptID, action: .retry)
        ])
        let replacement = try #require(await fixture.repository.task(taskID))

        await fixture.service.receive(
            .staged(
                .init(
                    taskID: taskID, attemptID: original.attemptID,
                    relativePath: "\(taskID.uuidString)/\(original.attemptID.uuidString).mp4"),
                nativeID: try #require(original.nativeID)))

        #expect(replacement.attemptID != original.attemptID)
        #expect((try await fixture.repository.task(taskID))?.attemptID == replacement.attemptID)
    }

    @Test func backgroundCompletionWaitsForDrainAcknowledgement() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = try BackgroundSessionDriver(
            stagingRoot: root.appending(path: "Staging"),
            resumeRoot: root.appending(path: "Resume"))
        let probe = await MainActor.run { CompletionProbe() }
        let identifier = BackgroundSessionDriver.cellularAllowedIdentifier
        let token = UUID()

        await driver.registerBackgroundCompletion(identifier: identifier) {
            probe.calls += 1
        }
        await driver.emit(.drain(identifier: identifier, token: token))
        #expect(await MainActor.run { probe.calls } == 0)
        await driver.acknowledgeDrain(identifier: identifier, token: token)
        #expect(await MainActor.run { probe.calls } == 1)
    }

    @Test func drainReconcilesAdoptedFileBeforeAcknowledgement() async throws {
        let fixture = try Fixture()
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        let staged = StagedFile(
            taskID: taskID, attemptID: task.attemptID,
            relativePath: "\(taskID.uuidString)/\(task.attemptID.uuidString).mp4")
        await fixture.driver.storeStaged(staged)

        let drained = await fixture.service.receive(.drain(identifier: "fixture", token: UUID()))

        #expect(drained)
        guard case .completed = try #require(await fixture.repository.task(taskID)).state else {
            Issue.record("Drain acknowledged before durable publication")
            return
        }
    }

    @Test func earlyFailureBeforeNativeCommitIsRecovered() async throws {
        let fixture = try Fixture()
        await fixture.driver.beforeReturn { task in
            let event = TransferEvent.failed(
                taskID: task.id, attemptID: task.attemptID,
                nativeID: .init(session: "fixture", task: 1),
                reason: "HTTP 503", resume: nil)
            await fixture.driver.storeFailure(event)
            await fixture.service.receive(event)
        }

        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let state = try #require(await fixture.repository.task(taskID)).state
        #expect(state == .transferFailed(reason: "HTTP 503", resume: nil))
    }

    @Test func earlyFailureSurvivesJournalWriteFailureInMemory() async throws {
        let fixture = try Fixture()
        let drainProbe = DrainProbe()
        await fixture.driver.beforeReturn { task in
            let event = TransferEvent.failed(
                taskID: task.id, attemptID: task.attemptID,
                nativeID: .init(session: "fixture", task: 1),
                reason: "Storage full", resume: nil)
            await fixture.service.receive(event)
            let drained = await fixture.service.receive(
                .drain(identifier: "fixture", token: UUID()))
            await drainProbe.record(drained)
        }

        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)

        #expect(await drainProbe.drained == false)
        #expect(
            (try await fixture.repository.task(taskID))?.state
                == .transferFailed(reason: "Storage full", resume: nil))
    }

    @Test func stagedSuccessClearsPendingEarlyFailureBeforeDrain() async throws {
        let fixture = try Fixture()
        await fixture.driver.beforeReturn { task in
            let nativeID = NativeTransferID(session: "fixture", task: 1)
            await fixture.service.receive(
                .failed(
                    taskID: task.id, attemptID: task.attemptID, nativeID: nativeID,
                    reason: "Obsolete failure", resume: nil))
            let staged = StagedFile(
                taskID: task.id, attemptID: task.attemptID,
                relativePath: "\(task.id.uuidString)/\(task.attemptID.uuidString).mp4")
            await fixture.driver.storeStaged(staged)
            await fixture.service.receive(.staged(staged, nativeID: nativeID))
        }

        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        guard case .completed = task.state else {
            Issue.record("Staged success did not win over the early failure")
            return
        }
        #expect(await fixture.service.receive(.drain(identifier: "fixture", token: UUID())))
    }

    @Test func relaunchedQueuedAttemptRecoversDurableFailureWithoutNativeTask() async throws {
        let fixture = try Fixture()
        let reserved = try await fixture.repository.reserve(fixture.request())
        await fixture.driver.storeFailure(
            .failed(
                taskID: reserved.id, attemptID: reserved.attemptID,
                nativeID: .init(session: "fixture", task: 17),
                reason: "HTTP 503", resume: nil))

        try await fixture.service.reconcile()

        #expect(
            (try await fixture.repository.task(reserved.id))?.state
                == .transferFailed(reason: "HTTP 503", resume: nil))
    }

    @Test func earlyStagedResumePublishesAfterNewNativeCommit() async throws {
        let fixture = try Fixture()
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let initial = try #require(await fixture.repository.task(taskID))
        _ = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: initial.attemptID, action: .pause)
        ])
        let paused = try #require(await fixture.repository.task(taskID))
        await fixture.driver.beforeReturn { task in
            let staged = StagedFile(
                taskID: task.id, attemptID: task.attemptID,
                relativePath: "\(task.id.uuidString)/\(task.attemptID.uuidString).mp4")
            await fixture.driver.storeStaged(staged)
            await fixture.service.receive(
                .staged(
                    staged, nativeID: .init(session: "fixture", task: 2)))
        }

        _ = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: paused.attemptID, action: .resume)
        ])

        guard case .completed = try #require(await fixture.repository.task(taskID)).state else {
            Issue.record("Early staged file was not recovered after resume")
            return
        }
    }

    @Test func earlyFailureDuringResumeIsRecovered() async throws {
        let fixture = try Fixture()
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let initial = try #require(await fixture.repository.task(taskID))
        _ = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: initial.attemptID, action: .pause)
        ])
        let paused = try #require(await fixture.repository.task(taskID))
        await fixture.driver.beforeReturn { task in
            let event = TransferEvent.failed(
                taskID: task.id, attemptID: task.attemptID,
                nativeID: .init(session: "fixture", task: 2), reason: "HTTP 503", resume: nil)
            await fixture.driver.storeFailure(event)
            await fixture.service.receive(event)
        }

        _ = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: paused.attemptID, action: .resume)
        ])

        #expect(
            (try await fixture.repository.task(taskID))?.state
                == .transferFailed(reason: "HTTP 503", resume: nil))
    }

    @Test func failureReceiptSurvivesStoreRecreation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskID = UUID()
        let attemptID = UUID()
        let nativeID = NativeTransferID(session: "fixture", task: 7)
        let first = try TerminalFailureStore(root: root)
        try first.save(
            .failed(
                taskID: taskID, attemptID: attemptID, nativeID: nativeID,
                reason: "HTTP 503", resume: nil))

        let restored = try TerminalFailureStore(root: root)
        guard
            case .failed(_, _, let recoveredNative, let reason, _) = try restored.event(
                taskID: taskID, attemptID: attemptID)
        else {
            Issue.record("Failure receipt did not survive store recreation")
            return
        }
        #expect(recoveredNative == nativeID)
        #expect(reason == "HTTP 503")
    }

    @Test func resumeDataPrunesOnlyUnreferencedAttempts() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ResumeDataStore(root: root)
        let taskID = UUID()
        let keepAttempt = UUID()
        let removeAttempt = UUID()
        let savedKeep = try store.save(
            Data([1, 2, 3]), taskID: taskID, attemptID: keepAttempt)
        let savedRemove = try store.save(
            Data([4, 5, 6]), taskID: taskID, attemptID: removeAttempt)
        let keep = try #require(savedKeep)
        let remove = try #require(savedRemove)
        let oldDate = Date.now.addingTimeInterval(-7200)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: root.appending(path: remove.relativePath).path)

        try store.prune(keepingAttempts: [keepAttempt])

        #expect(try store.load(keep, taskID: taskID, attemptID: keepAttempt) == Data([1, 2, 3]))
        #expect(throws: ResumeDataError.self) {
            try store.load(remove, taskID: taskID, attemptID: removeAttempt)
        }
    }

    @Test func newerDrainCannotUsePreviousAcknowledgement() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = try BackgroundSessionDriver(
            stagingRoot: root.appending(path: "Staging"),
            resumeRoot: root.appending(path: "Resume"))
        let probe = await MainActor.run { CompletionProbe() }
        let identifier = BackgroundSessionDriver.cellularAllowedIdentifier
        let first = UUID()
        let second = UUID()

        await driver.emit(.drain(identifier: identifier, token: first))
        await driver.acknowledgeDrain(identifier: identifier, token: first)
        await driver.emit(.drain(identifier: identifier, token: second))
        await driver.registerBackgroundCompletion(identifier: identifier) {
            probe.calls += 1
        }

        #expect(await MainActor.run { probe.calls } == 0)
        await driver.acknowledgeDrain(identifier: identifier, token: second)
        #expect(await MainActor.run { probe.calls } == 1)
    }

    @Test func callbackAfterDrainInvalidatesOutstandingToken() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = try BackgroundSessionDriver(
            stagingRoot: root.appending(path: "Staging"),
            resumeRoot: root.appending(path: "Resume"))
        let probe = await MainActor.run { CompletionProbe() }
        let identifier = BackgroundSessionDriver.cellularAllowedIdentifier
        let first = UUID()
        let second = UUID()
        await driver.registerBackgroundCompletion(identifier: identifier) {
            probe.calls += 1
        }

        await driver.emit(.drain(identifier: identifier, token: first))
        await driver.emit(
            .progress(
                taskID: UUID(), attemptID: UUID(),
                nativeID: .init(session: identifier, task: 1), received: 1, total: nil))
        await driver.acknowledgeDrain(identifier: identifier, token: first)
        #expect(await MainActor.run { probe.calls } == 0)

        await driver.emit(.drain(identifier: identifier, token: second))
        await driver.acknowledgeDrain(identifier: identifier, token: second)
        #expect(await MainActor.run { probe.calls } == 1)
    }

    @Test func obsoleteAttemptStagingIsCleanedOnCallbackAndReconcile() async throws {
        let fixture = try Fixture()
        let publisher = CleanupProbePublisher()
        let service = DownloadCoordinator(
            repository: fixture.repository, transfer: fixture.driver, publisher: publisher)
        let taskID = try #require((await service.start([try fixture.request()])).accepted.first)
        let original = try #require(await fixture.repository.task(taskID))
        _ = await service.perform([
            .init(taskID: taskID, expectedAttempt: original.attemptID, action: .cancel)
        ])
        _ = await service.perform([
            .init(taskID: taskID, expectedAttempt: original.attemptID, action: .retry)
        ])
        let old = StagedFile(
            taskID: taskID, attemptID: original.attemptID,
            relativePath: "\(taskID.uuidString)/\(original.attemptID.uuidString).mp4")
        await fixture.driver.storeStaged(old)

        await service.receive(.staged(old, nativeID: try #require(original.nativeID)))
        #expect(await publisher.cleaned.contains(old))

        await publisher.reset()
        try await service.reconcile()
        #expect(await publisher.cleaned.contains(old))
    }

    @Test func stagedCallbackAfterPausePublishesCompletedBytes() async throws {
        let fixture = try Fixture()
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let initial = try #require(await fixture.repository.task(taskID))
        _ = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: initial.attemptID, action: .pause)
        ])
        let staged = StagedFile(
            taskID: taskID, attemptID: initial.attemptID,
            relativePath: "\(taskID.uuidString)/\(initial.attemptID.uuidString).mp4")
        await fixture.driver.storeStaged(staged)

        await fixture.service.receive(
            .staged(
                staged, nativeID: try #require(initial.nativeID)))

        guard case .completed = try #require(await fixture.repository.task(taskID)).state else {
            Issue.record("Completed bytes arrived after pause but were stranded")
            return
        }
    }

    @Test func pausedReconciliationDoesNotReattachPreviousNativeTask() async throws {
        let fixture = try Fixture()
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let initial = try #require(await fixture.repository.task(taskID))
        _ = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: initial.attemptID, action: .pause)
        ])
        let paused = try #require(await fixture.repository.task(taskID))
        await fixture.driver.prepend(
            .init(
                id: try #require(initial.nativeID), taskID: taskID,
                attemptID: initial.attemptID, state: .completed))

        try await fixture.service.reconcile()

        #expect((try await fixture.repository.task(taskID))?.state == paused.state)
    }

    @Test func failureReconciliationKeepsTerminalReason() async throws {
        let fixture = try Fixture()
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        await fixture.service.receive(
            .failed(
                taskID: taskID, attemptID: task.attemptID,
                nativeID: try #require(task.nativeID), reason: "HTTP 503", resume: nil))

        try await fixture.service.reconcile()

        #expect(
            (try await fixture.repository.task(taskID))?.state
                == .transferFailed(reason: "HTTP 503", resume: nil))
    }

    @Test func missingFileRestoresAfterExternalAccessReturns() async throws {
        let fixture = try Fixture()
        let publisher = CleanupProbePublisher()
        let service = DownloadCoordinator(
            repository: fixture.repository, transfer: fixture.driver, publisher: publisher)
        let taskID = try #require((await service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        let staged = StagedFile(
            taskID: taskID, attemptID: task.attemptID,
            relativePath: "\(taskID.uuidString)/\(task.attemptID.uuidString).mp4")
        await service.receive(.staged(staged, nativeID: try #require(task.nativeID)))
        await publisher.setExists(false)
        try await service.reconcile()
        guard case .missingFile = try #require(await fixture.repository.task(taskID)).state else {
            Issue.record("Expected temporarily inaccessible file")
            return
        }

        await publisher.setExists(true)
        try await service.reconcile()
        guard case .completed = try #require(await fixture.repository.task(taskID)).state else {
            Issue.record("Accessible file did not restore completed state")
            return
        }
    }

    @Test func invalidMediaDiscardsStageAndOffersFreshTransferRetry() async throws {
        let fixture = try Fixture()
        let publisher = FailingPublisher(kind: .invalidMedia)
        let service = DownloadCoordinator(
            repository: fixture.repository, transfer: fixture.driver, publisher: publisher)
        let taskID = try #require((await service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        let staged = StagedFile(
            taskID: taskID, attemptID: task.attemptID,
            relativePath: "\(taskID.uuidString)/\(task.attemptID.uuidString).mp4")

        await service.receive(.staged(staged, nativeID: try #require(task.nativeID)))

        #expect(
            (try await fixture.repository.task(taskID))?.state
                == .transferFailed(reason: "下载内容不是可播放的视频，请重新下载。", resume: nil))
        #expect(await publisher.cleaned.contains(staged))
        let retry = await service.perform([
            .init(taskID: taskID, expectedAttempt: task.attemptID, action: .retry)
        ])
        #expect(retry.accepted == [taskID])
    }

    @Test func recoverablePublicationFailureRetainsStagedRetry() async throws {
        let fixture = try Fixture()
        let publisher = FailingPublisher(kind: .accessDenied)
        let service = DownloadCoordinator(
            repository: fixture.repository, transfer: fixture.driver, publisher: publisher)
        let taskID = try #require((await service.start([try fixture.request()])).accepted.first)
        let task = try #require(await fixture.repository.task(taskID))
        let staged = StagedFile(
            taskID: taskID, attemptID: task.attemptID,
            relativePath: "\(taskID.uuidString)/\(task.attemptID.uuidString).mp4")

        await service.receive(.staged(staged, nativeID: try #require(task.nativeID)))

        #expect(
            (try await fixture.repository.task(taskID))?.state
                == .publicationFailed(reason: "无法访问下载目录，请重新授权。", staged: staged))
        #expect(await publisher.cleaned.isEmpty)
    }
}

@MainActor private final class CompletionProbe {
    var calls = 0
}

private actor CleanupProbePublisher: FilePublisher {
    private(set) var cleaned: [StagedFile] = []
    private var fileExists = true

    func publish(_ staged: StagedFile, for task: DownloadTask) async throws -> PublishedFile {
        PublishedFile(
            destination: task.destination, relativeFilename: task.filename,
            byteSize: 1, fileIdentity: "fixture")
    }

    func cleanup(_ staged: StagedFile) async throws { cleaned.append(staged) }
    func reset() { cleaned.removeAll() }
    func setExists(_ value: Bool) { fileExists = value }
    func exists(_ file: PublishedFile) async -> Bool { fileExists }
    func delete(_ file: PublishedFile) async throws {}
}

private actor FailingPublisher: FilePublisher {
    enum Kind: Sendable { case invalidMedia, accessDenied }
    let kind: Kind
    private(set) var cleaned: [StagedFile] = []

    init(kind: Kind) { self.kind = kind }

    func publish(_ staged: StagedFile, for task: DownloadTask) async throws -> PublishedFile {
        switch kind {
        case .invalidMedia: throw DownloadFileError.invalidMedia
        case .accessDenied: throw DownloadFileError.accessDenied
        }
    }
    func cleanup(_ staged: StagedFile) async throws { cleaned.append(staged) }
    func exists(_ file: PublishedFile) async -> Bool { false }
    func delete(_ file: PublishedFile) async throws {}
}

private actor DrainProbe {
    private(set) var drained: Bool?
    func record(_ value: Bool) { drained = value }
}
