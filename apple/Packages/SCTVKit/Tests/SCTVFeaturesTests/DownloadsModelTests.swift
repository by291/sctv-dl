import Foundation
import SCTVCore
import Testing

@testable import SCTVFeatures

private actor DownloadListFixture: DownloadService {
    let task: DownloadTask
    var shouldFailReconciliation = false
    func setReconciliationFailure(_ value: Bool) { shouldFailReconciliation = value }
    var commands: [DownloadCommand] = []
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
        if shouldFailReconciliation { throw CocoaError(.fileReadNoPermission) }
    }
}

@MainActor struct DownloadsModelTests {
    @Test func failedReconciliationBlocksCommandsUntilExplicitRetry() async throws {
        let service = try DownloadListFixture()
        await service.setReconciliationFailure(true)
        let model = DownloadsModel(service: service)
        await model.load()
        for _ in 0..<50 where model.tasks.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let task = await service.task

        #expect(model.isReconciling)
        #expect(model.warning != nil)
        #expect(model.commands(for: .cancel, ids: [task.id]).isEmpty)
        await model.perform([
            DownloadCommand(taskID: task.id, expectedAttempt: task.attemptID, action: .cancel)
        ])
        #expect(await service.commands.isEmpty)

        await service.setReconciliationFailure(false)
        await model.reconcile()
        #expect(!model.isReconciling)
        #expect(model.warning == nil)
        #expect(model.commands(for: .cancel, ids: [task.id]).count == 1)
    }

    @Test func filterClearsSelectionAndCommandsPinAttempt() async throws {
        let service = try DownloadListFixture()
        let model = DownloadsModel(service: service)
        await model.load()
        for _ in 0..<50 where model.tasks.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let task = await service.task
        model.setSelection([task.id])
        await model.perform(.cancel)
        #expect(await service.commands.first?.expectedAttempt == task.attemptID)
        model.setSelection([task.id])
        model.selectFilter(.completed)
        #expect(model.selection.isEmpty)
        #expect(model.visibleTasks.isEmpty)
    }
}
