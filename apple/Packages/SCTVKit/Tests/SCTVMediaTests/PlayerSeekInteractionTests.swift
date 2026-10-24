import Foundation
import Testing

@testable import SCTVMedia

@MainActor
struct PlayerSeekInteractionTests {
    @Test func latestSeekWaitsForOldCompletionAndKeepsItsPreview() async {
        let interaction = PlayerSeekInteraction()
        let overlay = PlayerOverlayState()
        let gate = SeekGate()
        let latestGate = SeekGate()
        var applied: [Int64] = []
        let first = interaction.seek(to: 1000, owner: UUID(), overlay: overlay) {
            await gate.wait()
            applied.append(1000)
        } onFailure: { _ in
            Issue.record("Cancelled seek reported a failure")
        }
        while !gate.waiting { await Task.yield() }

        let latest = interaction.seek(to: 3000, owner: UUID(), overlay: overlay) {
            applied.append(3000)
            await latestGate.wait()
        } onFailure: { _ in
            Issue.record("Latest seek failed")
        }
        #expect(overlay.previewMilliseconds == 3000)
        #expect(applied.isEmpty)

        gate.release()
        await first.value
        while !latestGate.waiting { await Task.yield() }
        #expect(overlay.previewMilliseconds == 3000)
        latestGate.release()
        await latest.value
        #expect(applied == [1000, 3000])
        #expect(overlay.previewMilliseconds == nil)
        #expect(!overlay.isInteracting)
    }

    @Test func cancelledQueuedSeekNeverReachesThePlayer() async {
        let interaction = PlayerSeekInteraction()
        let overlay = PlayerOverlayState()
        let gate = SeekGate()
        let first = interaction.seek(to: 1000, owner: UUID(), overlay: overlay) {
            await gate.wait()
        } onFailure: { _ in
            Issue.record("First seek failed")
        }
        while !gate.waiting { await Task.yield() }
        var skippedTargetApplied = false
        let skipped = interaction.seek(to: 2000, owner: UUID(), overlay: overlay) {
            skippedTargetApplied = true
        } onFailure: { _ in
            Issue.record("Cancelled queued seek failed")
        }
        let latest = interaction.seek(to: 3000, owner: UUID(), overlay: overlay) {
        } onFailure: { _ in
            Issue.record("Latest seek failed")
        }

        gate.release()
        await first.value
        await skipped.value
        await latest.value
        #expect(!skippedTargetApplied)
        #expect(overlay.previewMilliseconds == nil)
    }

    @Test func disposalSuppressesLateFailureAndPreservesOtherOwnersPreview() async {
        let interaction = PlayerSeekInteraction()
        let overlay = PlayerOverlayState()
        let owner = UUID()
        let gate = SeekGate()
        let task = interaction.seek(to: 1000, owner: owner, overlay: overlay) {
            await gate.wait()
            throw CocoaError(.fileReadUnknown)
        } onFailure: { _ in
            Issue.record("Disposed seek reported a failure")
        }
        while !gate.waiting { await Task.yield() }
        interaction.cancel(owner: UUID())
        #expect(overlay.previewMilliseconds == 1000)
        interaction.cancel(owner: owner)
        #expect(overlay.previewMilliseconds == nil)
        let next = overlay.beginSeekPreview(at: 5000)
        overlay.setOptionsPresented(true, id: "speed")
        gate.release()
        await task.value
        #expect(overlay.previewMilliseconds == 5000)
        overlay.finishSeekPreview(next)
        #expect(overlay.isInteracting)
    }
}

@MainActor
private final class SeekGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
