import Foundation

public struct PlaybackRequestResolver: Sendable {
    private let api: any ProgrammeAPI
    private let history: any HistoryRepository

    public init(
        api: any ProgrammeAPI, history: any HistoryRepository
    ) {
        self.api = api
        self.history = history
    }

    public func resolve(_ saved: HistoryEntry, quality: VideoQuality) async throws
        -> PlaybackRequest
    {
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

    public func prepare(
        _ content: ProgrammeContent, programme: Programme, broadcast: BroadcastDate,
        quality: VideoQuality, resumeOverride: Int64? = nil
    ) async throws -> PlaybackRequest {
        let reference = try ContentRef(
            programmeID: programme.id, dateID: broadcast.id, contentID: content.id)
        let sources = try QualityResolver.variants(content)
        let selected = try QualityResolver.resolve(
            content, requested: quality)
        // History is optional: an unavailable history store must not prevent playback.
        let previous = try? await history.entries().first { $0.content == reference }
        let resume =
            resumeOverride ?? previous.map {
                HistoryRules.resumePosition(positionMs: $0.positionMs, completed: $0.completed)
            } ?? 0
        return PlaybackRequest(
            programme: .init(
                content: reference, title: content.title, programmeName: programme.name,
                broadcastDate: broadcast.date, cover: content.cover),
            source: .online(sources, quality: selected.quality),
            start: .init(positionMilliseconds: resume))
    }

    public enum PreparationError: LocalizedError, Equatable {
        case removed
        public var errorDescription: String? { "The programme is no longer available." }
    }
}
