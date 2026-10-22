import Foundation
import Observation
import SCTVCore

@MainActor @Observable
public final class PlaybackHistoryRecorder {
    public private(set) var warning: String?

    private let repository: any HistoryRepository
    private let now: @MainActor () -> Double
    private var session: HistorySession?
    private var playbackSessionID: UUID?
    private var sequence: UInt64 = 0
    private var lastSavedAt: Double?
    private var lastSaved: PlaybackSnapshot?
    private var observation: Task<Void, Never>?

    public init(
        repository: any HistoryRepository,
        now: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.repository = repository
        self.now = now
    }

    isolated deinit { observation?.cancel() }

    public func bind(request: PlaybackRequest, playbackSessionID: UUID) async throws {
        observation?.cancel()
        self.playbackSessionID = playbackSessionID
        session = nil
        sequence = 0
        lastSaved = nil
        lastSavedAt = nil
        let token = try await repository.begin(request)
        guard self.playbackSessionID == playbackSessionID else { return }
        session = token
        warning = nil
    }

    public func observe(_ playback: any PlaybackService) {
        observation?.cancel()
        observation = Task { [weak self] in
            for await snapshot in playback.snapshots() {
                guard !Task.isCancelled else { break }
                await self?.consume(snapshot)
            }
        }
    }

    public func flush(_ playback: any PlaybackService) async {
        if let snapshot = playback.capture() { await consume(snapshot, force: true) }
    }

    public func consume(_ sample: PlaybackSnapshot, force: Bool = false) async {
        guard sample.settled, sample.sessionID == playbackSessionID, let session else { return }
        let timestamp = now()
        let boundary =
            force || sample.reason != .progress || sample.playIntent == .paused || sample.ended
        if !boundary, let lastSavedAt, timestamp - lastSavedAt < 5 { return }
        if !force, let previous = lastSaved,
            previous.positionMs == sample.positionMs, previous.playIntent == sample.playIntent,
            previous.ended == sample.ended, previous.quality == sample.quality
        {
            return
        }

        sequence &+= 1
        let writeSequence = sequence
        do {
            try await repository.record(sample, session: session.id, sequence: writeSequence)
            // A late persistence completion cannot update the new session's throttle or warning.
            guard self.session?.id == session.id, sequence == writeSequence else { return }
            lastSaved = sample
            lastSavedAt = timestamp
            warning = nil
        } catch {
            guard self.session?.id == session.id, sequence == writeSequence else { return }
            warning = "观看记录尚未保存：\(error.localizedDescription)"
        }
    }
}
