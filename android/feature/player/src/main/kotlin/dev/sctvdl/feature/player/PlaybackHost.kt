package dev.sctvdl.feature.player

import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.player.ui.PlayerGestureEnvironment
import kotlinx.coroutines.flow.StateFlow

/** Activity window/PiP integration; binding a session does not transfer its destination-owned lifetime. */
interface PlaybackHost {
    val gestureEnvironment: PlayerGestureEnvironment? get() = null
    val pictureInPicture: StateFlow<Boolean>
    val supportsPictureInPicture: Boolean

    /** Expose the destination-owned session to Activity lifecycle and PiP callbacks. */
    fun bindPlayer(session: PlayerSession)

    /** Stop Activity callbacks for this session before the destination releases it. */
    fun unbindPlayer(session: PlayerSession)

    /** Apply the committed destination’s fullscreen window policy. */
    fun fullscreen(enabled: Boolean)

    /** Request PiP for the bound session and report whether the host accepted it. */
    fun enterPictureInPicture(): Boolean
}
