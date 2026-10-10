package dev.sctvdl.feature.player

import dev.sctvdl.player.media3.PlayerSession
import kotlinx.coroutines.flow.StateFlow

interface PlaybackHost {
    val pictureInPicture: StateFlow<Boolean>
    val supportsPictureInPicture: Boolean
    fun bindPlayer(session: PlayerSession)
    fun unbindPlayer(session: PlayerSession)
    fun fullscreen(enabled: Boolean)
    fun enterPictureInPicture(): Boolean
}
