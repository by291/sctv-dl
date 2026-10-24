import Foundation

public struct MediaSource: Equatable, Sendable {
    public let url: URL
    public let quality: VideoQuality
    public let headers: [String: String]

    public init(url: URL, quality: VideoQuality) throws {
        self.url = try MediaURLPolicy.validate(url)
        self.quality = quality
        self.headers = [
            "Referer": "https://scgc.video.play/",
            "User-Agent": UpstreamRequestProfile.userAgent,
        ]
    }
}
