import Foundation
import SCTVCore
import SCTVData
import Testing

@testable import SCTVDownloads

struct DownloadTransitionTests {
    @Test func capabilitiesDistinguishResumeFromRestartAndPublicationRetry() {
        #expect(!DownloadState.paused(resume: nil).allows(.resume))
        #expect(DownloadState.paused(resume: nil).allows(.retry))
        let staged = StagedFile(taskID: UUID(), attemptID: UUID(), relativePath: "staging.mp4")
        #expect(
            DownloadState.publicationFailed(reason: "disk full", staged: staged).allows(
                .retryPublication))
        #expect(
            !DownloadState.publicationFailed(reason: "disk full", staged: staged).allows(.retry))
    }

    @Test func oldAttemptCannotMutateRetry() async throws {
        let fixture = try Fixture()
        let request = try fixture.request()
        let accepted = await fixture.service.start([request])
        let taskID = try #require(accepted.accepted.first)
        let old = try #require(await fixture.repository.task(taskID))
        await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: old.attemptID, action: .cancel)
        ])
        await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: old.attemptID, action: .retry)
        ])
        let retried = try #require(await fixture.repository.task(taskID))
        #expect(retried.attemptID != old.attemptID)
        await fixture.service.receive(
            .progress(
                taskID: taskID, attemptID: old.attemptID,
                nativeID: .init(session: "fixture", task: 1), received: 90, total: 100))
        let after = try #require(await fixture.repository.task(taskID))
        #expect(after.attemptID == retried.attemptID)
        #expect(after.state == retried.state)
    }

    @Test func reservesContentAndActualQualityOnce() async throws {
        let fixture = try Fixture()
        let request = try fixture.request()
        async let first = fixture.service.start([request])
        async let second = fixture.service.start([request])
        let results = await (first, second)
        #expect(results.0.accepted.count + results.1.accepted.count == 1)
        #expect((try await fixture.repository.all()).count == 1)
        #expect(await fixture.driver.enqueues == 1)
    }

    @Test func batchRejectsMoreThan100() async throws {
        let fixture = try Fixture()
        let requests = try (1...101).map { try fixture.request(contentID: String($0)) }
        let result = await fixture.service.start(requests)
        #expect(result.accepted.isEmpty)
        #expect(result.failures.count == 101)
        #expect((try await fixture.repository.all()).isEmpty)
    }

    @Test func partialBatchKeepsValidReservation() async throws {
        let fixture = try Fixture()
        let request = try fixture.request()
        let result = await fixture.service.start([request, request])
        #expect(result.accepted.count == 1)
        #expect(result.failures.map(\.reason) == [.duplicate])
        #expect((try await fixture.repository.all()).count == 1)
    }

    @Test func wrongNativeIDCannotChangeProgress() async throws {
        let fixture = try Fixture()
        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let before = try #require(await fixture.repository.task(taskID))
        await fixture.service.receive(
            .progress(
                taskID: taskID, attemptID: before.attemptID,
                nativeID: .init(session: "fixture", task: 999), received: 90, total: 100))
        #expect((try await fixture.repository.task(taskID))?.state == before.state)
        await fixture.service.receive(
            .progress(
                taskID: taskID, attemptID: before.attemptID,
                nativeID: try #require(before.nativeID), received: 90, total: 100))
        #expect(
            (try await fixture.repository.task(taskID))?.state
                == .transferring(received: 90, total: 100))
    }

    @Test func commandsRejectMoreThan100DistinctTasks() async throws {
        let fixture = try Fixture()
        let first = await fixture.service.start(
            try (1...100).map { try fixture.request(contentID: String($0)) })
        let last = await fixture.service.start([try fixture.request(contentID: "101")])
        let tasks = try await fixture.repository.all()
        #expect(first.accepted.count + last.accepted.count == 101)
        let commands = tasks.map {
            DownloadCommand(taskID: $0.id, expectedAttempt: $0.attemptID, action: .cancel)
        }
        let result = await fixture.service.perform(commands)
        #expect(result.accepted.isEmpty)
        #expect(result.failures.count == 101)
        #expect((try await fixture.repository.all()).allSatisfy { $0.state.isTransferActive })
    }

    @Test func twoObserversReceiveAuthoritativeReplacement() async throws {
        let fixture = try Fixture()
        let first = await fixture.service.updates()
        let second = await fixture.service.updates()
        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()
        _ = await firstIterator.next()
        _ = await secondIterator.next()

        let taskID = try #require(
            (await fixture.service.start([try fixture.request()])).accepted.first)
        let firstSnapshot = try #require(await firstIterator.next())
        let secondSnapshot = try #require(await secondIterator.next())
        #expect(firstSnapshot.tasks.map(\.id) == [taskID])
        #expect(secondSnapshot.tasks.map(\.id) == [taskID])

        let task = try #require(await fixture.repository.task(taskID))
        _ = await fixture.service.perform([
            .init(taskID: taskID, expectedAttempt: task.attemptID, action: .cancel)
        ])
        let cancelled = try #require(await firstIterator.next())
        #expect(cancelled.revision > firstSnapshot.revision)
        #expect(cancelled.tasks.first?.state == .cancelled)
    }
}
