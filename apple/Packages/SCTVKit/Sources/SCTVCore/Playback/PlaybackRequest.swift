import Foundation

/// Pins the selected media and its initial playback state for a native session.
public struct PlaybackRequest: Sendable {
    public struct ProgrammeDetails: Sendable {
        public let content: ContentRef
        public let title: String
        public let programmeName: String
        public let broadcastDate: String
        public let cover: URL?

        /// Captures the programme identity and display text available at selection time.
        public init(
            content: ContentRef, title: String,
            programmeName: String = "", broadcastDate: String = "", cover: URL? = nil
        ) {
            self.content = content
            self.title = title
            self.programmeName = programmeName
            self.broadcastDate = broadcastDate
            self.cover = cover
        }
    }

    public enum Source: Sendable {
        case online([MediaSource], quality: VideoQuality)
        case local(LocalFileLease, quality: VideoQuality, onlineMetadata: [MediaSource] = [])
    }

    public struct Start: Sendable {
        public let positionMilliseconds: Int64
        public let speed: Double

        /// Normalizes the starting position and rate accepted by the player.
        public init(positionMilliseconds: Int64 = 0, speed: Double = 1) {
            self.positionMilliseconds = max(0, positionMilliseconds)
            self.speed = speed.isFinite && speed > 0 && speed <= 4 ? speed : 1
        }
    }

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

    /// Creates an open request for exactly one kind of media source.
    public init(
        programme: ProgrammeDetails, source: Source, start: Start = Start()
    ) {
        content = programme.content
        title = programme.title
        programmeName = programme.programmeName
        broadcastDate = programme.broadcastDate
        cover = programme.cover
        resumeMilliseconds = start.positionMilliseconds
        speed = start.speed

        switch source {
        case .online(let variants, let selectedQuality):
            localFile = nil
            sources = variants
            quality = selectedQuality
        case .local(let lease, let publishedQuality, let onlineMetadata):
            localFile = lease
            sources = onlineMetadata
            quality = publishedQuality
        }
    }

    /// Adapts older callers that supply a local lease alongside online metadata.
    public init(
        content: ContentRef, title: String, sources: [MediaSource], quality: VideoQuality,
        resumeMilliseconds: Int64 = 0, speed: Double = 1,
        programmeName: String = "", broadcastDate: String = "", cover: URL? = nil,
        localFile: LocalFileLease? = nil
    ) {
        let programme = ProgrammeDetails(
            content: content, title: title, programmeName: programmeName,
            broadcastDate: broadcastDate, cover: cover)
        let source =
            localFile.map { Source.local($0, quality: quality, onlineMetadata: sources) }
            ?? .online(sources, quality: quality)
        self.init(
            programme: programme, source: source,
            start: Start(positionMilliseconds: resumeMilliseconds, speed: speed))
    }
}
