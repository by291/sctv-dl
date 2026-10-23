import Testing

@testable import SCTVMedia

struct PlayerInteractionTests {
    @Test @MainActor func releasedSeekKeepsTargetUntilCompletion() {
        let overlay = PlayerOverlayState()
        let token = overlay.beginSeekPreview(at: 8_000)
        #expect(overlay.previewMilliseconds == 8_000)
        #expect(overlay.isInteracting)

        overlay.finishSeekPreview(token)
        #expect(overlay.previewMilliseconds == nil)
        #expect(!overlay.isInteracting)
    }

    @Test @MainActor func olderSeekCompletionCannotClearNewPreview() {
        let overlay = PlayerOverlayState()
        let old = overlay.beginSeekPreview(at: 8_000)
        let current = overlay.beginSeekPreview(at: 3_000)

        overlay.finishSeekPreview(old)
        #expect(overlay.previewMilliseconds == 3_000)
        #expect(overlay.isInteracting)
        overlay.finishSeekPreview(current)
        #expect(overlay.previewMilliseconds == nil)
    }

    @Test func seekPreviewIsBoundedAndProportional() {
        #expect(
            PlayerInteraction.seek(position: 30_000, duration: 600_000, delta: 100, width: 400)
                == 60_000)
        #expect(
            PlayerInteraction.seek(position: 3_000, duration: 12_000, delta: -400, width: 400) == 0)
        #expect(
            PlayerInteraction.seek(position: 3_000, duration: 12_000, delta: 400, width: 400)
                == 12_000)
        #expect(
            PlayerInteraction.seek(position: 3_000, duration: 12_000, delta: 40, width: 0) == 3_000)
    }

    @Test func verticalAdjustmentClampsAndReversesScreenDirection() {
        #expect(PlayerInteraction.level(initial: 0.5, delta: -100, height: 400) == 0.75)
        #expect(PlayerInteraction.level(initial: 0.5, delta: 900, height: 400) == 0)
        #expect(PlayerInteraction.level(initial: 0.5, delta: -900, height: 400) == 1)
    }
}
