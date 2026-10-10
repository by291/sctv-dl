package dev.sctvdl.feature.player

import dev.sctvdl.player.media3.PlayerSession
import kotlinx.coroutines.flow.MutableStateFlow

internal class TestPlaybackHost : PlaybackHost {
    override val pictureInPicture = MutableStateFlow(false)
    override val supportsPictureInPicture = true
    override fun bindPlayer(session: PlayerSession) = Unit
    override fun unbindPlayer(session: PlayerSession) = Unit
    override fun fullscreen(enabled: Boolean) = Unit
    override fun enterPictureInPicture() = false
}
