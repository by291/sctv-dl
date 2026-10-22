import Foundation

@MainActor
public protocol PlaybackService: AnyObject {
    func open(_ request: PlaybackRequest) async throws -> UUID
    func setPlaybackIntent(_ intent: PlaybackIntent)
    func setSpeed(_ speed: Double)
    func seek(to milliseconds: Int64) async throws
    func switchQuality(_ quality: VideoQuality) async throws
    func retry() async throws
    func capture() -> PlaybackSnapshot?
    func beginDismissal()
    func cancelDismissal()
    func finishDismissal() async
    func snapshots() -> AsyncStream<PlaybackSnapshot>
}
