import SCTVCore
import SCTVDownloads
import SCTVFeatures
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
        let accepted = Set(result.acceptedContent)
        let fallback = Set(
            prepared.prepared.compactMap { item -> ContentRef? in
                guard item.source.quality != quality, accepted.contains(item.content) else {
                    return nil
                }
                return item.content
            }
        ).count
        return "已添加 \(result.accepted.count) 个下载"
            + (fallback > 0 ? "，其中 \(fallback) 项使用可用画质" : "")
            + (failed > 0 ? "；\(failed) 项未添加，请检查任务列表或稍后重试。" : "。")
    }

    func playbackFailureMessage(_ error: any Error) -> String {
        if let fileError = error as? DownloadFileError {
            return DownloadIssueMessage.text(for: fileError.issueCode)
        }
        if error as? PlaybackRequestResolver.PreparationError == .removed {
            return "该节目已不可用，请刷新后重试。"
        }

        return error.localizedDescription
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
            programme: .init(
                content: task.content, title: task.title, programmeName: task.programmeName,
                broadcastDate: task.broadcastDate, cover: task.cover),
            source: .local(lease, quality: task.quality),
            start: .init(positionMilliseconds: resume))
    }
}
