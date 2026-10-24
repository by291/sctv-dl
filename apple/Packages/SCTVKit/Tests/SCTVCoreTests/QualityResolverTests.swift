import Foundation
import Testing

@testable import SCTVCore

struct QualityResolverTests {
    @Test func deduplicatesAndFallsBack() throws {
        let smooth = URL(string: "https://fscgc.scgchc.com/smooth.mp4")!
        let content = ProgrammeContent(
            id: "3", title: "节目", cover: nil, video: nil, smoothVideo: smooth, publishedAt: nil)
        let source = try QualityResolver.resolve(
            content, requested: .standard)

        #expect(source.quality == .smooth)
        #expect(
            source.headers == [
                "Referer": "https://scgc.video.play/", "User-Agent": "okhttp/4.12.0",
            ])

        let duplicated = ProgrammeContent(
            id: "3", title: "节目", cover: nil, video: smooth, smoothVideo: smooth, publishedAt: nil)
        #expect(try QualityResolver.variants(duplicated).count == 1)
    }

    @Test func rejectsForbiddenSourceAndMissingVideo() {
        let invalid = ProgrammeContent(
            id: "3", title: "节目", cover: nil, video: URL(string: "https://example.com/a.mp4"),
            smoothVideo: nil, publishedAt: nil)
        #expect(throws: (any Error).self) {
            try QualityResolver.resolve(invalid, requested: .standard)
        }
        let empty = ProgrammeContent(
            id: "3", title: "节目", cover: nil, video: nil, smoothVideo: nil, publishedAt: nil)
        #expect(throws: QualityResolver.ResolutionError.self) {
            try QualityResolver.resolve(empty, requested: .smooth)
        }
    }
}
