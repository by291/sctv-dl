import Foundation
import SCTVCore
import Testing

@testable import SCTVFeatures

private actor DownloadListFixture: DownloadService {
    let task: DownloadTask
    var shouldFailReconciliation = false
    var commands: [DownloadCommand] = []
    var reconciliationStarted = false
    private var holdsReconciliation = false
    private var reconciliationContinuation: CheckedContinuation<Void, Never>?

    init() throws {
        task = DownloadTask(
            id: UUID(), attemptID: UUID(), revision: 1,
            content: try ContentRef(programmeID: "1", dateID: "2", contentID: "3"),
            programmeName: "News", broadcastDate: "2026-10-22", title: "News", cover: nil,
            quality: .standard,
            source: DownloadSource(
                try MediaSource(
                    url: URL(string: "https://fscgc.scgchc.com/test.mp4")!, quality: .standard)),
            filename: "News.mp4", allowsCellular: false,
            destination: .applicationManaged, nativeID: nil, state: .queued, createdAt: Date())
    }

    func setReconciliationFailure(_ value: Bool) { shouldFailReconciliation = value }

    func holdReconciliation() { holdsReconciliation = true }

    func finishReconciliation() {
        holdsReconciliation = false
        reconciliationContinuation?.resume()
        reconciliationContinuation = nil
    }

    func start(_ requests: [DownloadRequest]) async -> DownloadBatchResult {
        DownloadBatchResult(accepted: [], failures: [])
    }

    func perform(_ commands: [DownloadCommand]) async -> DownloadBatchResult {
        self.commands = commands
        return DownloadBatchResult(accepted: commands.map(\.taskID), failures: [])
    }

    func updates() async -> AsyncStream<DownloadSnapshot> {
        AsyncStream { $0.yield(DownloadSnapshot(revision: 1, tasks: [task])) }
    }

    func reconcile() async throws {
        reconciliationStarted = true
        if holdsReconciliation {
            await withCheckedContinuation { reconciliationContinuation = $0 }
        }
        if shouldFailReconciliation { throw CocoaError(.fileReadNoPermission) }
    }
}

@MainActor struct DownloadsModelTests {
    @Test func recoveryBlocksCommandsBeforeAndDuringLoading() async throws {
        let service = try DownloadListFixture()
        await service.holdReconciliation()
        let model = DownloadsModel(service: service)
        let task = service.task
        let command = DownloadCommand(
            taskID: task.id, expectedAttempt: task.attemptID, action: .cancel)

        #expect(model.recoveryState == .loading)
        #expect(!model.canPerformCommands)
        await model.perform([command])
        #expect(await service.commands.isEmpty)

        let loading = Task { await model.load() }
        for _ in 0..<50 where !(await service.reconciliationStarted) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await service.reconciliationStarted)
        for _ in 0..<50 where model.tasks.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.tasks.map(\.id) == [task.id])
        #expect(model.recoveryState == .loading)
        #expect(model.commands(for: .cancel, ids: [task.id]).isEmpty)
        await model.perform([command])
        #expect(await service.commands.isEmpty)

        await service.finishReconciliation()
        await loading.value
        #expect(model.recoveryState == .ready)
        #expect(model.canPerformCommands)
        await model.perform([command])
        #expect(await service.commands.count == 1)
        #expect(await service.commands.first?.expectedAttempt == task.attemptID)
    }

    @Test func failedReconciliationBlocksCommandsUntilExplicitRetry() async throws {
        let service = try DownloadListFixture()
        await service.setReconciliationFailure(true)
        let model = DownloadsModel(service: service)
        await model.load()
        for _ in 0..<50 where model.tasks.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let task = service.task

        guard case .failed(let message) = model.recoveryState else {
            Issue.record("Failed recovery must retain the error and block commands")
            return
        }
        #expect(message == "下载状态尚未恢复：\(CocoaError(.fileReadNoPermission).localizedDescription)")
        #expect(model.warning == message)
        #expect(!model.canPerformCommands)
        #expect(model.commands(for: .cancel, ids: [task.id]).isEmpty)
        await model.perform([
            DownloadCommand(taskID: task.id, expectedAttempt: task.attemptID, action: .cancel)
        ])
        #expect(await service.commands.isEmpty)

        await service.setReconciliationFailure(false)
        await model.reconcile()
        #expect(model.recoveryState == .ready)
        #expect(model.canPerformCommands)
        #expect(model.warning == nil)
        let commands = model.commands(for: .cancel, ids: [task.id])
        #expect(commands.count == 1)
        await model.perform(commands)
        #expect(await service.commands.first?.taskID == task.id)
        #expect(await service.commands.first?.expectedAttempt == task.attemptID)
    }

    @Test func filterClearsSelectionAndCommandsPinAttempt() async throws {
        let service = try DownloadListFixture()
        let model = DownloadsModel(service: service)
        await model.load()
        for _ in 0..<50 where model.tasks.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let task = service.task
        model.setSelection([task.id])

        await model.perform(.cancel)

        #expect(await service.commands.first?.expectedAttempt == task.attemptID)
        model.setSelection([task.id])
        model.selectFilter(.completed)
        #expect(model.selection.isEmpty)
        #expect(model.visibleTasks.isEmpty)
    }
}
