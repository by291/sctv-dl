import Foundation
import Observation
import SCTVCore

public enum DownloadFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case active = "进行中"
    case completed = "已完成"
    case attention = "需处理"
    public var id: String { rawValue }
    func includes(_ state: DownloadState) -> Bool {
        switch self {
        case .all: true
        case .active:
            switch state {
            case .queued, .transferring, .publishing: true
            default: false
            }
        case .completed:
            if case .completed = state { true } else { false }
        case .attention:
            switch state {
            case .interrupted, .transferFailed, .publicationFailed, .missingFile, .paused: true
            default: false
            }
        }
    }
}

@MainActor @Observable
public final class DownloadsModel {
    public private(set) var tasks: [DownloadTask] = []
    public private(set) var filter = DownloadFilter.all
    public private(set) var selection: Set<UUID> = []
    public private(set) var isReconciling = true
    public private(set) var warning: String?
    public var anchors: [DownloadFilter: UUID] = [:]
    private let service: any DownloadService
    private var observation: Task<Void, Never>?
    private var revision: UInt64 = 0

    public init(service: any DownloadService) { self.service = service }
    public var visibleTasks: [DownloadTask] { tasks.filter { filter.includes($0.state) } }

    public func load() async {
        guard observation == nil else { return }
        let source = await service.updates()
        observation = Task { [weak self] in
            for await snapshot in source {
                guard !Task.isCancelled, let self, snapshot.revision >= revision else { continue }
                revision = snapshot.revision
                tasks = snapshot.tasks
                selection.formIntersection(Set(visibleTasks.map(\.id)))
            }
        }
        await reconcile()
    }

    public func reconcile() async {
        isReconciling = true
        do {
            try await service.reconcile()
            warning = nil
            isReconciling = false
        } catch { warning = "下载状态尚未恢复：\(error.localizedDescription)" }
    }

    public func selectFilter(_ filter: DownloadFilter) {
        self.filter = filter
        selection = []
    }
    public func setSelection(_ ids: Set<UUID>) {
        selection = ids.intersection(visibleTasks.map(\.id))
    }

    public func commands(for action: DownloadAction, ids: Set<UUID>? = nil) -> [DownloadCommand] {
        guard !isReconciling else { return [] }
        let requested = ids ?? selection
        return tasks.filter { requested.contains($0.id) && $0.state.allows(action) }
            .map { DownloadCommand(taskID: $0.id, expectedAttempt: $0.attemptID, action: action) }
    }

    public func perform(_ action: DownloadAction) async { await perform(commands(for: action)) }
    public func perform(_ commands: [DownloadCommand]) async {
        guard !commands.isEmpty, !isReconciling else { return }
        let result = await service.perform(commands)
        warning = result.failures.isEmpty ? nil : "有 \(result.failures.count) 项操作未完成，请检查任务状态后重试。"
        selection.subtract(result.accepted)
    }

    isolated deinit { observation?.cancel() }
}
