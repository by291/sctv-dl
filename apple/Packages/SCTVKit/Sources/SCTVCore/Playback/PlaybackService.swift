import Foundation

/// Controls playback and observes the current native session.
@MainActor
public protocol PlaybackService: AnyObject {
    /// Opens the requested media paused and returns its session identity after the initial seek.
    func open(_ request: PlaybackRequest) async throws -> UUID

    /// Sets the play or pause intent that pending native work must respect.
    func setPlaybackIntent(_ intent: PlaybackIntent)

    /// Changes the selected playback rate without changing play intent.
    func setSpeed(_ speed: Double)

    /// Seeks a ready source; a superseded native seek throws cancellation.
    func seek(to milliseconds: Int64) async throws

    /// Replaces the online variant while preserving the last settled position.
    func switchQuality(_ quality: VideoQuality) async throws

    /// Retries the accepted source and returns the recovered session identity.
    @discardableResult
    func retry() async throws -> UUID

    /// Reads the current sample, or the last usable sample while the source settles.
    func capture() -> PlaybackSnapshot?

    /// Revokes playback intent unless a native picture-in-picture surface retains playback.
    func beginDismissal()

    /// Allows playback actions again when dismissal is abandoned.
    func cancelDismissal()

    /// Releases a dismissing session after its picture-in-picture owner clears.
    func finishDismissal() async

    /// Yields the current sample when available, then buffers only the newest sample.
    func snapshots() -> AsyncStream<PlaybackSnapshot>
}
