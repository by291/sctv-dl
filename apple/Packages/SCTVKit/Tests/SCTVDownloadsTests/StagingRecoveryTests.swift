import Foundation
import SCTVCore
import Testing

@testable import SCTVDownloads

struct StagingRecoveryTests {
    @Test func callbackFileSurvivesDelegateReturn() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let temporary = root.appending(path: "callback.tmp")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("fixture media".utf8).write(to: temporary)

        let taskID = UUID()
        let attemptID = UUID()
        let store = try DownloadStagingStore(root: root.appending(path: "Staging"))
        let staged = try store.adoptTemporaryFile(
            at: temporary, taskID: taskID, attemptID: attemptID)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        try? FileManager.default.removeItem(at: temporary)

        #expect(staged.relativePath == "\(taskID.uuidString)/\(attemptID.uuidString).mp4")
        #expect(try store.stagedFile(taskID: taskID, attemptID: attemptID) == staged)
        #expect(
            FileManager.default.fileExists(
                atPath: root.appending(path: "Staging").appending(path: staged.relativePath).path))
    }

    @Test func delegateAdoptsBeforeCallbackLocationExpires() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let temporary = root.appending(path: "callback.tmp")
        try Data("fixture media".utf8).write(to: temporary)
        let staging = try DownloadStagingStore(root: root.appending(path: "Staging"))
        let resumes = try ResumeDataStore(root: root.appending(path: "Resume"))
        let failures = try TerminalFailureStore(root: root.appending(path: "Failures"))
        let delegate = BackgroundSessionDelegate(
            identifier: "fixture", staging: staging, resumes: resumes, failures: failures)
        let taskID = UUID()
        let attemptID = UUID()

        let event = delegate.adoptCallbackFile(
            at: temporary, taskID: taskID, attemptID: attemptID,
            nativeID: .init(session: "fixture", task: 1), statusCode: 200)
        try? FileManager.default.removeItem(at: temporary)

        guard case .staged(let staged, _) = event else {
            Issue.record("Expected staged callback")
            return
        }
        #expect(try staging.stagedFile(taskID: taskID, attemptID: attemptID) == staged)
    }

    @Test func stagedIdentitySurvivesStoreRecreation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let temporary = root.appending(path: "callback.tmp")
        try Data("fixture media".utf8).write(to: temporary)
        let taskID = UUID()
        let attemptID = UUID()
        let stagingRoot = root.appending(path: "Staging")
        let first = try DownloadStagingStore(root: stagingRoot)
        let staged = try first.adoptTemporaryFile(
            at: temporary, taskID: taskID, attemptID: attemptID)

        let restored = try DownloadStagingStore(root: stagingRoot)
        #expect(try restored.stagedFile(taskID: taskID, attemptID: attemptID) == staged)
        #expect(try restored.stagedFile(taskID: taskID, attemptID: UUID()) == nil)
    }
}
