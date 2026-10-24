import Foundation
import SCTVCore
import Testing

@testable import SCTVDownloads

struct FilePublicationTests {
    @Test func publicationRetainsStagingUntilGuardedCommitAndRecovers() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try fixture(root)
        let first = try await fixture.publisher.publish(fixture.staged, for: fixture.task)
        #expect(FileManager.default.fileExists(atPath: fixture.source.path))
        let second = try await fixture.publisher.publish(fixture.staged, for: fixture.task)
        #expect(first == second)
        #expect(await fixture.publisher.exists(first))
        try await fixture.publisher.cleanup(fixture.staged)
        #expect(!FileManager.default.fileExists(atPath: fixture.source.path))
        #expect(await fixture.publisher.exists(first))
        try await fixture.publisher.delete(first)
        #expect(!(await fixture.publisher.exists(first)))
    }

    @Test func revokedBookmarkRetainsStagedBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try fixture(root, destination: .external(bookmarkID: UUID()))
        await #expect(throws: (any Error).self) {
            try await fixture.publisher.publish(fixture.staged, for: fixture.task)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    @Test func sameNameNeverOverwritesUnrelatedFile() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try fixture(root)
        let path = root.appending(
            path:
                "files/News-\(fixture.task.id.uuidString)-\(fixture.task.attemptID.uuidString).mp4")
        try Data("unrelated".utf8).write(to: path)
        let file = try await fixture.publisher.publish(fixture.staged, for: fixture.task)
        #expect(file.relativeFilename != path.lastPathComponent)
        #expect(try Data(contentsOf: path) == Data("unrelated".utf8))
    }

    @Test func rejectsHTTP200HTMLBodyAndKeepsStaging() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try fixture(root)
        try Data("<html>upstream error</html>".utf8).write(to: fixture.source)
        await #expect(throws: (any Error).self) {
            try await fixture.publisher.publish(fixture.staged, for: fixture.task)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    @Test func transientMediaValidationErrorPreservesCauseAndStaging() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try fixture(root)
        let failing = try LocalFilePublisher(
            staging: root.appending(path: "staging"), managed: root.appending(path: "files"),
            directories: SecurityScopedDirectories(storage: root.appending(path: "bookmarks")),
            isPlayable: { _ in throw CocoaError(.fileReadNoPermission) })

        await #expect(throws: CocoaError.self) {
            try await failing.publish(fixture.staged, for: fixture.task)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.source.path))
        let retried = try await fixture.publisher.publish(fixture.staged, for: fixture.task)
        #expect(await fixture.publisher.exists(retried))
    }

    @Test func diskFullRetainsStagedFileForPublicationRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try fixture(root)
        let failing = try LocalFilePublisher(
            staging: root.appending(path: "staging"), managed: root.appending(path: "files"),
            directories: SecurityScopedDirectories(storage: root.appending(path: "bookmarks")),
            copyFile: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        await #expect(throws: CocoaError.self) {
            try await failing.publish(fixture.staged, for: fixture.task)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.source.path))
        let retried = try await fixture.publisher.publish(fixture.staged, for: fixture.task)
        #expect(await fixture.publisher.exists(retried))
    }

    @Test func rejectsEscapingAndSymlinkPaths() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: DownloadFileError.self) { try confinedFile("../secret", under: root) }
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "link"), withDestinationURL: root.deletingLastPathComponent())
        #expect(throws: DownloadFileError.self) { try confinedFile("link/secret", under: root) }
    }

    private func fixture(_ root: URL, destination: FileDestination = .applicationManaged) throws
        -> (publisher: LocalFilePublisher, task: DownloadTask, staged: StagedFile, source: URL)
    {
        let task = DownloadTask(
            id: UUID(), attemptID: UUID(), revision: 0,
            content: try ContentRef(programmeID: "1", dateID: "2", contentID: "3"),
            programmeName: "News", broadcastDate: "2026-10-22", title: "News", cover: nil,
            quality: .standard,
            source: DownloadSource(
                try MediaSource(
                    url: URL(string: "https://fscgc.scgchc.com/test.mp4")!, quality: .standard)),
            filename: "News.mp4", allowsCellular: false,
            destination: destination, nativeID: nil, state: .queued, createdAt: Date())
        let staged = StagedFile(
            taskID: task.id, attemptID: task.attemptID,
            relativePath: "\(task.id.uuidString)/\(task.attemptID.uuidString).mp4")
        let source = root.appending(path: "staging/" + staged.relativePath)
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        let video = try #require(
            Bundle.module.url(forResource: "probe", withExtension: "mp4", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: video, to: source)
        let directories = SecurityScopedDirectories(storage: root.appending(path: "bookmarks"))
        let publisher = try LocalFilePublisher(
            staging: root.appending(path: "staging"), managed: root.appending(path: "files"),
            directories: directories)
        return (publisher, task, staged, source)
    }
}
