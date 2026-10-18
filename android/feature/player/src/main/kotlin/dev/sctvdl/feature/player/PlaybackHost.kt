package dev.sctvdl.feature.player

import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.player.ui.PlayerGestureEnvironment
import kotlinx.coroutines.flow.StateFlow

/** Activity window/PiP integration; binding a session does not transfer its destination-owned lifetime. */
interface PlaybackHost {
    val gestureEnvironment: PlayerGestureEnvironment? get() = null
    val pictureInPicture: StateFlow<Boolean>
    val supportsPictureInPicture: Boolean

    fun bindPlayer(session: PlayerSession)

    fun unbindPlayer(session: PlayerSession)

    fun fullscreen(enabled: Boolean)

    fun enterPictureInPicture(): Boolean
}
