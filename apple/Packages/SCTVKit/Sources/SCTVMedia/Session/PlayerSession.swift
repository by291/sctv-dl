import Foundation
import Observation
import SCTVCore

@MainActor @Observable
public final class PlayerSession: Identifiable {
    /// Stable identity of the shared session, independent of presentations and native items.
    public let id = UUID()
    public let playback: PlaybackCoordinator
    public let recorder: PlaybackHistoryRecorder
    public private(set) var title = "播放器"
    public private(set) var details: PlayerDetails?
    public var warning: String?
    /// Identity owned by the currently presented player UI.
    public private(set) var presentationID = UUID()
    // A close has its own lifecycle identity without creating a new UI presentation.
    private var lifecycleID = UUID()
    private var latestRequestID = UUID()

    public init(
        history: any HistoryRepository, playback: PlaybackCoordinator = PlaybackCoordinator()
    ) {
        self.playback = playback
        recorder = PlaybackHistoryRecorder(repository: history)
    }

    /// Reserve before resolving metadata so older asynchronous taps cannot steal the player.
    public func reservePlaybackRequest() -> UUID {
        latestRequestID = UUID()
        return latestRequestID
    }

    public func isCurrentRequest(_ requestID: UUID) -> Bool { latestRequestID == requestID }

    /// Returns a presentation identity only for the latest metadata request.
    public func beginPresentation(forRequest requestID: UUID) -> UUID? {
        guard latestRequestID == requestID else { return nil }
        playback.seekInteraction.cancel()
        presentationID = UUID()
        lifecycleID = presentationID
        return presentationID
    }

    /// Opens only while this presentation still owns the session, including after history awaits.
    public func open(_ request: PlaybackRequest, forPresentation presentationID: UUID) async {
        guard lifecycleID == presentationID else { return }

        await recorder.flush(playback)
        guard lifecycleID == presentationID else { return }

        warning = nil
        title = request.title
        details = PlayerDetails(request)

        do {
            let playbackSessionID = try await playback.open(request)
            guard lifecycleID == presentationID else { return }

            do {
                try await recorder.bind(request: request, playbackSessionID: playbackSessionID)
                guard lifecycleID == presentationID else { return }
                recorder.observe(playback)
            } catch {
                if lifecycleID == presentationID {
                    warning = "观看记录尚不可用：\(error.localizedDescription)"
                }
            }
        } catch {
            if lifecycleID == presentationID { warning = error.localizedDescription }
        }
    }

    /// Releases only the specified presentation; a replacement survives asynchronous cleanup.
    public func close(presentationID: UUID) async {
        guard lifecycleID == presentationID else { return }

        latestRequestID = UUID()
        let closingLifecycleID = UUID()
        lifecycleID = closingLifecycleID
        playback.beginDismissal()

        await recorder.flush(playback)
        guard lifecycleID == closingLifecycleID else { return }
        await playback.finishDismissal()
    }
}
