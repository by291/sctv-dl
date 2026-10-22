import Foundation

public struct ProgrammeContent: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let cover: URL?
    public let video: URL?
    public let smoothVideo: URL?
    public let publishedAt: String?

    public init(
        id: String, title: String, cover: URL?, video: URL?, smoothVideo: URL?, publishedAt: String?
    ) {
        self.id = id
        self.title = title
        self.cover = cover
        self.video = video
        self.smoothVideo = smoothVideo
        self.publishedAt = publishedAt
    }
}
