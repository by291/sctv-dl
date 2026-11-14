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
    public private(set) var warning: String?

    /// Identity owned by the currently presented player UI.
    public private(set) var presentationID = UUID()

    // A close has its own lifecycle identity without creating a new UI presentation.
    private var lifecycleID = UUID()
    private var latestRequestID = UUID()
    private var latestActionID = UUID()

    private var acceptedRequest: PlaybackRequest?
    private var boundHistorySessionID: UUID?

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

    /// Checks whether an asynchronously resolved request still owns the latest tap.
    public func isCurrentRequest(_ requestID: UUID) -> Bool { latestRequestID == requestID }

    /// Returns a presentation identity only for the latest metadata request.
    public func beginPresentation(forRequest requestID: UUID) -> UUID? {
        guard latestRequestID == requestID else { return nil }
        playback.seekInteraction.cancel()
        presentationID = UUID()
        lifecycleID = presentationID
        playback.setPresentation(presentationID)
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
        acceptedRequest = request

        do {
            let playbackSessionID = try await playback.open(request)
            await bindHistory(
                request, playbackSessionID: playbackSessionID, forPresentation: presentationID)
        } catch is CancellationError {
            // The replacement or closing presentation owns what happens next.
        } catch {
            if lifecycleID == presentationID {
                warning = error.localizedDescription
            }
        }
    }

    /// Retries playback and establishes history if the first native open failed.
    public func retry(forPresentation presentationID: UUID) async {
        await performAction(forPresentation: presentationID) {
            guard let request = acceptedRequest else { return }
            let playbackSessionID = try await playback.retry()
            await bindHistory(
                request, playbackSessionID: playbackSessionID, forPresentation: presentationID)
        }
    }

    /// Selects a source for the presentation that initiated the request.
    func switchQuality(_ quality: VideoQuality, forPresentation presentationID: UUID) async {
        await performAction(forPresentation: presentationID) {
            try await playback.switchQuality(quality)
        }
    }

    /// Seeks to the beginning for the presentation that requested it.
    public func rewind(forPresentation presentationID: UUID) async {
        await performAction(forPresentation: presentationID) {
            try await playback.seek(to: 0)
        }
    }

    /// Reports an asynchronous player error only to the presentation that initiated it.
    public func reportWarning(_ message: String, forPresentation presentationID: UUID) {
        guard lifecycleID == presentationID else { return }
        warning = message
    }

    private func performAction(
        forPresentation presentationID: UUID,
        operation: () async throws -> Void
    ) async {
        guard lifecycleID == presentationID else { return }

        let actionID = UUID()
        latestActionID = actionID
        warning = nil
        do {
            try await operation()
        } catch is CancellationError {
            // A newer seek, quality choice, or presentation revoked this action.
        } catch {
            guard lifecycleID == presentationID, latestActionID == actionID else { return }
            warning = error.localizedDescription
        }
    }

    private func bindHistory(
        _ request: PlaybackRequest, playbackSessionID: UUID, forPresentation presentationID: UUID
    ) async {
        // Rebinding an already observed native session could undo a user's history deletion.
        guard lifecycleID == presentationID, boundHistorySessionID != playbackSessionID else {
            return
        }

        do {
            try await recorder.bind(request: request, playbackSessionID: playbackSessionID)
            guard lifecycleID == presentationID else { return }
            boundHistorySessionID = playbackSessionID
            recorder.observe(playback)
        } catch {
            guard lifecycleID == presentationID else { return }
            warning = "观看记录尚不可用：\(error.localizedDescription)"
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

        acceptedRequest = nil
        boundHistorySessionID = nil
        await playback.finishDismissal()
    }
}
