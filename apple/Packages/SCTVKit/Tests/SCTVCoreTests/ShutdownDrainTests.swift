import Foundation
import Testing

@testable import SCTVCore

@Suite(.timeLimit(.minutes(1)))
@MainActor struct ShutdownDrainTests {
    @Test func deadlineRepliesOnceEvenWhenWriterIgnoresCancellation() async {
        let drain = ShutdownDrain()
        let replies = AsyncStream<Bool>.makeStream()
        let writerFinished = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        var results: [Bool] = []

        await withCheckedContinuation { started in
            drain.start(timeout: .milliseconds(20)) {
                await withCheckedContinuation {
                    release = $0
                    started.resume()
                }
                writerFinished.continuation.yield(())
                writerFinished.continuation.finish()
            } completion: {
                results.append($0)
                replies.continuation.yield($0)
            }
        }

        // Wait for the deadline reply, not an assumed scheduling interval on a busy runner.
        var iterator = replies.stream.makeAsyncIterator()
        #expect(await iterator.next() == true)
        #expect(results == [true])

        // The writer deliberately ignores cancellation and settles only after the timeout.
        release?.resume()
        for await _ in writerFinished.stream {}
        #expect(results == [true])
        replies.continuation.finish()
    }

    @Test func settledWritesReplyWithoutWaitingForDeadline() async {
        let drain = ShutdownDrain()
        let timedOut = await withCheckedContinuation { reply in
            drain.start(timeout: .seconds(1)) {
            } completion: {
                reply.resume(returning: $0)
            }
        }
        #expect(!timedOut)
    }
}
