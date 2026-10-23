import Foundation
import Observation
import SCTVCore

@MainActor @Observable
public final class PlayerSession: Identifiable {
    public let id = UUID()
    public let playback: PlaybackCoordinator
    public let recorder: PlaybackHistoryRecorder
    public private(set) var title = "播放器"
    public private(set) var details: PlayerDetails?
    public var warning: String?
    public private(set) var presentationID = UUID()
    private var generation = UUID()
    private var requestID = UUID()

    public init(
        history: any HistoryRepository, playback: PlaybackCoordinator = PlaybackCoordinator()
    ) {
        self.playback = playback
        recorder = PlaybackHistoryRecorder(repository: history)
    }

    /// Reserve before resolving metadata so older asynchronous taps cannot steal the player.
    public func beginRequest() -> UUID {
        requestID = UUID()
        return requestID
    }

    public func isCurrentRequest(_ token: UUID) -> Bool { requestID == token }

    public func beginPresentation(for request: UUID) -> UUID? {
        guard requestID == request else { return nil }
        presentationID = UUID()
        generation = presentationID
        return presentationID
    }

    public func open(_ request: PlaybackRequest, expected token: UUID) async {
        guard generation == token else { return }
        await recorder.flush(playback)
        guard generation == token else { return }
        warning = nil
        title = request.title
        details = PlayerDetails(request)
        do {
            let native = try await playback.open(request)
            guard generation == token else { return }
            do {
                try await recorder.bind(request: request, playbackSessionID: native)
                guard generation == token else { return }
                recorder.observe(playback)
            } catch {
                if generation == token { warning = "观看记录尚不可用：\(error.localizedDescription)" }
            }
        } catch { if generation == token { warning = error.localizedDescription } }
    }

    public func close(expected token: UUID) async {
        guard generation == token else { return }
        requestID = UUID()
        let closing = UUID()
        generation = closing
        playback.beginDismissal()
        await recorder.flush(playback)
        guard generation == closing else { return }
        await playback.finishDismissal()
    }
}
