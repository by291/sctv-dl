package dev.sctvdl.player.ui

/** Window changes are temporary; media volume belongs to the user and is never restored. */
interface PlayerGestureEnvironment {
    fun captureBrightness() {}

    fun adjustBrightness(delta: Float): Int

    fun adjustVolume(delta: Float): Int

    fun restoreBrightness()

    fun needsGestureHint(): Boolean

    fun acknowledgeGestureHint()
}
