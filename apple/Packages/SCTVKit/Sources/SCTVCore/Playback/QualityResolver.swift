public enum QualityResolver {
    public enum ResolutionError: Error { case unavailable }

    public static func variants(_ content: ProgrammeContent) throws
        -> [MediaSource]
    {
        var sources: [MediaSource] = []
        for (quality, url) in [
            (VideoQuality.standard, content.video), (.smooth, content.smoothVideo),
        ] {
            guard let url, !sources.contains(where: { $0.url == url }) else { continue }
            sources.append(
                try MediaSource(url: url, quality: quality))
        }
        return sources
    }

    public static func resolve(
        _ content: ProgrammeContent, requested: VideoQuality
    ) throws -> MediaSource {
        let sources = try variants(content)
        guard let source = sources.first(where: { $0.quality == requested }) ?? sources.first else {
            throw ResolutionError.unavailable
        }
        return source
    }
}
