import Foundation

public struct DownloadRequest: Sendable {
    public let content: ContentRef
    public let programmeName: String
    public let broadcastDate: String
    public let title: String
    public let cover: URL?
    public let source: MediaSource
    public let filename: String
    public let allowsCellular: Bool
    public let destination: FileDestination

    public init(
        content: ContentRef, programmeName: String, broadcastDate: String, title: String,
        cover: URL?, source: MediaSource, filename: String, allowsCellular: Bool,
        destination: FileDestination
    ) {
        self.content = content
        self.programmeName = programmeName
        self.broadcastDate = broadcastDate
        self.title = title
        self.cover = cover
        self.source = source
        self.filename = filename
        self.allowsCellular = allowsCellular
        self.destination = destination
    }
}

public struct PreparedDownload: Sendable {
    public let content: ContentRef
    public let programmeName: String
    public let broadcastDate: String
    public let title: String
    public let cover: URL?
    public let source: MediaSource
    public let filename: String

    public func request(destination: FileDestination, allowsCellular: Bool) -> DownloadRequest {
        DownloadRequest(
            content: content, programmeName: programmeName, broadcastDate: broadcastDate,
            title: title, cover: cover, source: source, filename: filename,
            allowsCellular: allowsCellular, destination: destination)
    }
}

public struct DownloadPreparationResult: Sendable {
    public let prepared: [PreparedDownload]
    public let failures: [DownloadItemFailure]
}

public enum DownloadPreparation {
    public static func prepare(
        contents: [ProgrammeContent], programme: Programme, broadcast: BroadcastDate,
        requestedQuality: VideoQuality
    ) -> DownloadPreparationResult {
        var prepared: [PreparedDownload] = []
        var failures: [DownloadItemFailure] = []
        for content in contents {
            let ref: ContentRef
            do {
                ref = try ContentRef(
                    programmeID: programme.id, dateID: broadcast.id, contentID: content.id)
            } catch {
                failures.append(.init(reason: .storage("Invalid content identity")))
                continue
            }
            do {
                let source = try QualityResolver.resolve(
                    content, requested: requestedQuality)
                let filename = safeFilename(
                    date: broadcast.date, title: content.title, quality: source.quality)
                prepared.append(
                    .init(
                        content: ref, programmeName: programme.name, broadcastDate: broadcast.date,
                        title: content.title, cover: content.cover, source: source,
                        filename: filename))
            } catch {
                failures.append(.init(content: ref, reason: .transfer("No validated media source")))
            }
        }
        return .init(prepared: prepared, failures: failures)
    }

    private static func safeFilename(date: String, title: String, quality: VideoQuality) -> String {
        let label = quality == .standard ? "标准" : "流畅"
        let stem = "\(date)_\(title)_\(label)"
        let forbidden = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        let clean = String(
            stem.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }.joined().prefix(
                150)
        )
        .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return (clean.isEmpty ? "download" : clean) + ".mp4"
    }
}
