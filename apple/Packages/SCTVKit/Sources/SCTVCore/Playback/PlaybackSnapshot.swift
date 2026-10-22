import Foundation

public enum PlaybackIntent: Sendable { case paused, playing }

public enum PlaybackSampleReason: Sendable { case progress, seek, lifecycle }

public struct PlaybackSnapshot: Sendable {
    public let sessionID: UUID
    public let positionMs: Int64
    public let durationMs: Int64?
    public let quality: VideoQuality
    public let speed: Double
    public let playIntent: PlaybackIntent
    public let settled: Bool
    public let ended: Bool
    public let reason: PlaybackSampleReason

    public init(
        sessionID: UUID, positionMs: Int64, durationMs: Int64?, quality: VideoQuality,
        speed: Double, playIntent: PlaybackIntent, settled: Bool, ended: Bool,
        reason: PlaybackSampleReason = .progress
    ) {
        self.sessionID = sessionID
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.quality = quality
        self.speed = speed
        self.playIntent = playIntent
        self.settled = settled
        self.ended = ended
        self.reason = reason
    }
}
