import Foundation
import SCTVCore

struct PlaybackRequestResolver: Sendable {
    let api: any ProgrammeAPI
    let history: any HistoryRepository

    func resolve(_ saved: HistoryEntry, quality: VideoQuality) async throws -> PlaybackRequest {
        let content = saved.content
        let contents = try await api.contents(
            programmeID: content.programmeID, dateID: content.dateID)
        guard let item = contents.first(where: { $0.id == content.contentID }) else {
            throw PreparationError.removed
        }
        return try await prepare(
            item,
            programme: Programme(id: content.programmeID, name: saved.programmeName, cover: nil),
            broadcast: BroadcastDate(id: content.dateID, date: saved.broadcastDate),
            quality: quality,
            resumeOverride: HistoryRules.resumePosition(
                positionMs: saved.positionMs, completed: saved.completed))
    }

    func prepare(
        _ content: ProgrammeContent, programme: Programme, broadcast: BroadcastDate,
        quality: VideoQuality, resumeOverride: Int64? = nil
    ) async throws -> PlaybackRequest {
        let reference = try ContentRef(
            programmeID: programme.id, dateID: broadcast.id, contentID: content.id)
        let sources = try QualityResolver.variants(content, productVersion: "0.1.0")
        let selected = try QualityResolver.resolve(
            content, requested: quality, productVersion: "0.1.0")
        // History is optional: an unavailable history store must not prevent playback.
        let previous = try? await history.entries().first { $0.content == reference }
        let resume =
            resumeOverride ?? previous.map {
                HistoryRules.resumePosition(positionMs: $0.positionMs, completed: $0.completed)
            } ?? 0
        return PlaybackRequest(
            content: reference, title: content.title, sources: sources, quality: selected.quality,
            resumeMilliseconds: resume, programmeName: programme.name,
            broadcastDate: broadcast.date, cover: content.cover)
    }

    enum PreparationError: LocalizedError {
        case removed
        var errorDescription: String? { "该节目已不可用，请刷新后重试。" }
    }
}
