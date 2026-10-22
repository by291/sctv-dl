import Foundation
import GRDB
import SCTVCore
import Testing

@testable import SCTVData

struct HistoryRepositoryTests {
    private func repository() throws -> SQLiteHistoryRepository {
        let database = try DatabaseQueue()
        try UserMigrations.migrator.migrate(database)
        return SQLiteHistoryRepository(database: database)
    }

    private func request(_ contentID: String = "3") throws -> PlaybackRequest {
        PlaybackRequest(
            content: try ContentRef(programmeID: "1", dateID: "2", contentID: contentID),
            title: "Title", sources: [], quality: .standard, programmeName: "Programme",
            broadcastDate: "2026-10-22")
    }

    private func sample(_ position: Int64) -> PlaybackSnapshot {
        PlaybackSnapshot(
            sessionID: UUID(), positionMs: position, durationMs: 100000, quality: .standard,
            speed: 1, playIntent: .paused, settled: true, ended: false)
    }

    @Test func clearInvalidatesOpenSessions() async throws {
        let repository = try repository()
        let session = try await repository.begin(request())
        try await repository.record(sample(10000), session: session.id, sequence: 1)
        try await repository.clear()
        try await repository.record(sample(20000), session: session.id, sequence: 2)
        #expect(try await repository.entries().isEmpty)
    }

    @Test func newerSessionAndSequenceWin() async throws {
        let repository = try repository()
        let old = try await repository.begin(request())
        let new = try await repository.begin(request())
        try await repository.record(sample(30000), session: new.id, sequence: 2)
        try await repository.record(sample(20000), session: new.id, sequence: 1)
        try await repository.record(sample(10000), session: old.id, sequence: 3)
        #expect(try await repository.entries().first?.positionMs == 30000)
        try await repository.remove(request().content)
        try await repository.record(sample(40000), session: new.id, sequence: 4)
        #expect(try await repository.entries().isEmpty)
    }

    @Test func retainsNewest500() async throws {
        let repository = try repository()
        for index in 0..<505 {
            let session = try await repository.begin(request(String(index)))
            try await repository.record(sample(Int64(index)), session: session.id, sequence: 1)
        }
        let entries = try await repository.entries()
        #expect(entries.count == 500)
        #expect(entries.first?.content.contentID == "504")
        #expect(entries.last?.content.contentID == "5")
    }
}
