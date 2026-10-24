import SCTVCore
import SCTVMedia

/// Inputs captured by a workspace tap, before asynchronous request preparation begins.
enum PlaybackSelection {
    case history(HistoryEntry)
    case archive(ProgrammeContent, programme: Programme, broadcast: BroadcastDate)
    case download(DownloadTask)
}

/// Prepares programme actions; the workspace retains navigation and presentation ownership.
@MainActor
struct ProgrammeActions {
    let dependencies: AppDependencies

    func playbackRequest(for selection: PlaybackSelection) async throws -> PlaybackRequest {
        switch selection {
        case .history(let entry):
            return try await dependencies.resolver.resolve(
                entry, quality: dependencies.settings.value.playbackQuality)
        case .archive(let content, let programme, let broadcast):
            return try await dependencies.resolver.prepare(
                content, programme: programme, broadcast: broadcast,
                quality: dependencies.settings.value.playbackQuality)
        case .download(let task):
            return try await downloadedPlaybackRequest(for: task)
        }
    }

    func recoverAfterPlaybackFailure(for selection: PlaybackSelection) async {
        guard case .download = selection else { return }
        // Reconcile a potentially missing local file after reporting the playback error.
        // Recovery is best effort; its failure must not replace the original cause.
        try? await dependencies.downloads.service.reconcile()
    }

    func startDownloads(
        _ contents: [ProgrammeContent], programme: Programme, broadcast: BroadcastDate
    ) async -> String {
        await dependencies.downloads.start()
        if let warning = dependencies.downloads.warning { return warning }

        let quality = dependencies.settings.value.playbackQuality
        let prepared = DownloadPreparation.prepare(
            contents: contents, programme: programme, broadcast: broadcast,
            requestedQuality: quality)
        let result = await submit(prepared.prepared)

        let failed = prepared.failures.count + result.failures.count
        let fallback = prepared.prepared.filter { $0.source.quality != quality }.count
        return "已添加 \(result.accepted.count) 个下载"
            + (fallback > 0 ? "，其中 \(fallback) 项使用可用画质" : "")
            + (failed > 0 ? "；\(failed) 项未添加，请检查任务列表或稍后重试。" : "。")
    }

    /// Submits already prepared sources using the current destination and cellular policy.
    /// Callers await download startup before reaching this step.
    func submit(_ prepared: [PreparedDownload]) async -> DownloadBatchResult {
        let requests = prepared.map {
            $0.request(
                destination: dependencies.downloads.destination,
                allowsCellular: dependencies.settings.value.allowCellularDownloads)
        }
        return await dependencies.downloads.service.start(requests)
    }

    private func downloadedPlaybackRequest(for task: DownloadTask) async throws -> PlaybackRequest {
        let lease = try await dependencies.downloads.access.open(task.id)
        // History is optional, while the file lease remains owned by the request/session.
        let history = try? await dependencies.history.entries().first { $0.content == task.content }
        let resume =
            history.map {
                HistoryRules.resumePosition(positionMs: $0.positionMs, completed: $0.completed)
            } ?? 0

        return PlaybackRequest(
            content: task.content, title: task.title, sources: [], quality: task.quality,
            resumeMilliseconds: resume, programmeName: task.programmeName,
            broadcastDate: task.broadcastDate, cover: task.cover, localFile: lease)
    }
}
