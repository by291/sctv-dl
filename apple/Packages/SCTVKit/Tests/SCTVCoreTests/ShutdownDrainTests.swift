import Foundation
import Testing

@testable import SCTVCore

@MainActor struct ShutdownDrainTests {
    @Test func deadlineRepliesOnceEvenWhenWriterIgnoresCancellation() async throws {
        let drain = ShutdownDrain()
        var release: CheckedContinuation<Void, Never>?
        var results: [Bool] = []
        drain.start(timeout: .milliseconds(20)) {
            await withCheckedContinuation { release = $0 }
        } completion: {
            results.append($0)
        }

        try await Task.sleep(for: .milliseconds(60))
        #expect(results == [true])
        release?.resume()
        await Task.yield()
        #expect(results == [true])
    }

    @Test func settledWritesReplyWithoutWaitingForDeadline() async throws {
        let drain = ShutdownDrain()
        var results: [Bool] = []
        drain.start(timeout: .seconds(1)) {
        } completion: {
            results.append($0)
        }
        for _ in 0..<50 where results.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        #expect(results == [false])
    }
}
