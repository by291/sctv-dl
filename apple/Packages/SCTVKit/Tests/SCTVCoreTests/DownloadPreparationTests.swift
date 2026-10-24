import Foundation
import SCTVCore
import Testing

struct DownloadPreparationTests {
    private struct Fixture: Decodable {
        let title: String
        let date: String
        let requestedQuality: VideoQuality
        let video: URL?
        let smoothVideo: URL?
        let expectedQuality: VideoQuality
        let filename: String
    }

    @Test func matchesSharedDownloadNameAndQualityFixtures() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "download-names", withExtension: "json", subdirectory: "Fixtures"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        #expect(!fixtures.isEmpty)
        for fixture in fixtures {
            let content = ProgrammeContent(
                id: "3", title: fixture.title, cover: nil, video: fixture.video,
                smoothVideo: fixture.smoothVideo, publishedAt: nil)
            let result = DownloadPreparation.prepare(
                contents: [content], programme: Programme(id: "1", name: "News", cover: nil),
                broadcast: BroadcastDate(id: "2", date: fixture.date),
                requestedQuality: fixture.requestedQuality)
            #expect(result.prepared.first?.filename == fixture.filename)
            #expect(result.prepared.first?.source.quality == fixture.expectedQuality)
        }
    }

    @Test func pinsActualQualityAndSafeFilenameForMixedBatch() throws {
        let programme = Programme(id: "1", name: "News", cover: nil)
        let broadcast = BroadcastDate(id: "2", date: "2026-10-16")
        let valid = ProgrammeContent(
            id: "3", title: "News:/Clip", cover: nil,
            video: URL(string: "https://fscgc.scgchc.com/a.mp4"), smoothVideo: nil, publishedAt: nil
        )
        let invalid = ProgrammeContent(
            id: "4", title: "Unsafe", cover: nil,
            video: URL(string: "http://invalid.example/a.mp4"), smoothVideo: nil, publishedAt: nil)

        let result = DownloadPreparation.prepare(
            contents: [valid, invalid], programme: programme, broadcast: broadcast,
            requestedQuality: .smooth)
        #expect(result.prepared.count == 1)
        #expect(result.prepared.first?.source.quality == .standard)
        #expect(result.prepared.first?.filename == "2026-10-16_News__Clip_标准.mp4")
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.content?.contentID == "4")
    }
}
