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

    @Test func timedOutWriterCannotCompleteALaterDrain() async {
        let drain = ShutdownDrain()
        let firstReplies = AsyncStream<Bool>.makeStream()
        let firstWriterCompleted = AsyncStream<Void>.makeStream()
        let secondReplies = AsyncStream<Bool>.makeStream()
        var releaseFirst: CheckedContinuation<Void, Never>?
        var releaseSecond: CheckedContinuation<Void, Never>?
        var didSecondWriterFinish = false

        await withCheckedContinuation { started in
            drain.start(timeout: .milliseconds(20)) {
                await withCheckedContinuation {
                    releaseFirst = $0
                    started.resume()
                }
                firstWriterCompleted.continuation.finish()
            } completion: {
                firstReplies.continuation.yield($0)
                firstReplies.continuation.finish()
            }
        }

        var firstReply = firstReplies.stream.makeAsyncIterator()
        #expect(await firstReply.next() == true)

        await withCheckedContinuation { started in
            drain.start(timeout: .seconds(5)) {
                await withCheckedContinuation {
                    releaseSecond = $0
                    started.resume()
                }
                didSecondWriterFinish = true
            } completion: { timedOut in
                secondReplies.continuation.yield(didSecondWriterFinish && !timedOut)
                secondReplies.continuation.finish()
            }
        }

        releaseFirst?.resume()
        for await _ in firstWriterCompleted.stream {}
        releaseSecond?.resume()

        var secondReply = secondReplies.stream.makeAsyncIterator()
        #expect(await secondReply.next() == true)
    }
}
