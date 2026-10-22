import Foundation

public struct Preferences: Codable, Equatable, Sendable {
    public enum Appearance: String, Codable, Sendable, CaseIterable { case system, light, dark }

    private enum CodingKeys: String, CodingKey {
        case appearance, playbackQuality, allowCellularDownloads
    }

    public var appearance: Appearance
    public var playbackQuality: VideoQuality
    public var allowCellularDownloads: Bool

    public init(
        appearance: Appearance = .system,
        playbackQuality: VideoQuality = .standard,
        allowCellularDownloads: Bool = false
    ) {
        self.appearance = appearance
        self.playbackQuality = playbackQuality
        self.allowCellularDownloads = allowCellularDownloads
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = (try? values.decode(Appearance.self, forKey: .appearance)) ?? .system
        playbackQuality =
            (try? values.decode(VideoQuality.self, forKey: .playbackQuality)) ?? .standard
        allowCellularDownloads =
            (try? values.decode(Bool.self, forKey: .allowCellularDownloads)) ?? false
    }
}
