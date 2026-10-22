import Foundation

public struct PlaybackRequest: Sendable {
    public let content: ContentRef
    public let title: String
    public let programmeName: String
    public let broadcastDate: String
    public let cover: URL?
    public let localFile: LocalFileLease?
    public let sources: [MediaSource]
    public let quality: VideoQuality
    public let resumeMilliseconds: Int64
    public let speed: Double

    public init(
        content: ContentRef, title: String, sources: [MediaSource], quality: VideoQuality,
        resumeMilliseconds: Int64 = 0, speed: Double = 1,
        programmeName: String = "", broadcastDate: String = "", cover: URL? = nil,
        localFile: LocalFileLease? = nil
    ) {
        self.content = content
        self.title = title
        self.programmeName = programmeName
        self.broadcastDate = broadcastDate
        self.cover = cover
        self.localFile = localFile
        self.sources = sources
        self.quality = quality
        self.resumeMilliseconds = max(0, resumeMilliseconds)
        self.speed = speed.isFinite && speed > 0 && speed <= 4 ? speed : 1
    }
}
