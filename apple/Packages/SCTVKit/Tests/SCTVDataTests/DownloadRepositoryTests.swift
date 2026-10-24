import Foundation
import SCTVCore
import Testing

@testable import SCTVData

struct DownloadRepositoryTests {
    @Test func preservesCreationOrderAcrossProgressStateChangesAndReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = StorageLocations(root: root)
        let database = try DatabaseFactory.open(at: locations).runtime
        let repository = SQLiteDownloadRepository(database: database)
        var older = try await repository.reserve(request("1"))
        var newer = try await repository.reserve(request("2"))
        let expected = [newer.id, older.id]
        #expect(try await repository.all().map(\.id) == expected)

        // Alternating callbacks must update progress without moving either card.
        for received in [Int64(10), 20, 30] {
            older = try await update(
                older, to: .transferring(received: received, total: 100), in: repository)
            #expect(try await repository.all().map(\.id) == expected)
            newer = try await update(
                newer, to: .transferring(received: received, total: 100), in: repository)
            #expect(try await repository.all().map(\.id) == expected)
        }

        older = try await update(older, to: .paused(resume: nil), in: repository)
        #expect(try await repository.all().map(\.id) == expected)
        let retried = older.replacing(attemptID: UUID(), state: .queued)
        #expect(
            try await repository.commit(
                retried, expectedRevision: older.revision, expectedAttempt: older.attemptID))
        #expect(try await repository.all().map(\.id) == expected)

        let reopened = SQLiteDownloadRepository(
            database: try DatabaseFactory.open(at: locations).runtime)
        #expect(try await reopened.all().map(\.id) == expected)
        #expect(try await reopened.task(newer.id)?.state == newer.state)
        let latest = try await reopened.reserve(request("3"))
        #expect(try await reopened.all().map(\.id) == [latest.id] + expected)
    }

    private func update(
        _ task: DownloadTask, to state: DownloadState, in repository: SQLiteDownloadRepository
    ) async throws -> DownloadTask {
        let updated = task.replacing(state: state)
        #expect(
            try await repository.commit(
                updated, expectedRevision: task.revision, expectedAttempt: task.attemptID))
        return updated
    }

    private func request(_ contentID: String) throws -> DownloadRequest {
        DownloadRequest(
            content: try ContentRef(programmeID: "1", dateID: "2", contentID: contentID),
            programmeName: "News", broadcastDate: "2026-10-24", title: "Clip", cover: nil,
            source: try MediaSource(
                url: URL(string: "https://fscgc.scgchc.com/a.mp4")!, quality: .standard),
            filename: "Clip.mp4", allowsCellular: false, destination: .applicationManaged)
    }
}
