public enum QualityResolver {
    public enum ResolutionError: Error { case unavailable }

    public static func variants(_ content: ProgrammeContent, productVersion: String) throws
        -> [MediaSource]
    {
        var sources: [MediaSource] = []
        for (quality, url) in [
            (VideoQuality.standard, content.video), (.smooth, content.smoothVideo),
        ] {
            guard let url, !sources.contains(where: { $0.url == url }) else { continue }
            sources.append(
                try MediaSource(url: url, quality: quality, productVersion: productVersion))
        }
        return sources
    }

    public static func resolve(
        _ content: ProgrammeContent, requested: VideoQuality, productVersion: String
    ) throws -> MediaSource {
        let sources = try variants(content, productVersion: productVersion)
        guard let source = sources.first(where: { $0.quality == requested }) ?? sources.first else {
            throw ResolutionError.unavailable
        }
        return source
    }
}
