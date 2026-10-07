@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.player

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import dev.sctvdl.domain.Quality
import okhttp3.OkHttpClient

class PlayerSession(context: Context, initialQuality: Quality = Quality.Standard) {
    private val backend = ExoBackend(context.applicationContext)
    val player: ExoPlayer get() = backend.player
    val controller = PlaybackController(backend, initialQuality)
    fun release() = controller.release()
}

private class ExoBackend(context: Context) : PlaybackBackend {
    private val client = OkHttpClient.Builder().followRedirects(
        false
    ).followSslRedirects(false).build()
    private val http = OkHttpDataSource.Factory(
        client
    ).setDefaultRequestProperties(mapOf("Referer" to "https://scgc.video.play/"))
    val player = ExoPlayer.Builder(context)
        .setMediaSourceFactory(DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http)))
        .build().apply {
            setAudioAttributes(
                AudioAttributes.Builder().setUsage(
                    C.USAGE_MEDIA
                ).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
                true
            )
            setHandleAudioBecomingNoisy(true)
        }
    private val session = MediaSession.Builder(
        context,
        player
    ).setId(java.util.UUID.randomUUID().toString()).build()
    private var callback: ((Long, BackendSnapshot) -> Unit)? = null

    init {
        player.addListener(object : Player.Listener {
            override fun onEvents(player: Player, events: Player.Events) {
                player.currentMediaItem?.mediaId?.toLongOrNull()?.let {
                    callback?.invoke(it, snapshot())
                }
            }
        })
    }

    override val positionMs get() = player.currentPosition.coerceAtLeast(0)
    override var playWhenReady: Boolean
        get() = player.playWhenReady
        set(value) {
            player.playWhenReady = value
        }
    override var speed: Float
        get() = player.playbackParameters.speed
        set(value) {
            player.playbackParameters = PlaybackParameters(value)
        }
    override fun setListener(listener: (Long, BackendSnapshot) -> Unit) {
        callback = listener
    }
    override fun setMedia(uri: String, token: Long, positionMs: Long) {
        player.setMediaItem(
            MediaItem.Builder().setUri(uri).setMediaId(token.toString()).build(),
            positionMs
        )
    }
    override fun prepare() = player.prepare()
    override fun seekTo(positionMs: Long) = player.seekTo(positionMs)
    override fun snapshot() = BackendSnapshot(
        positionMs,
        player.duration.takeIf {
            it > 0 &&
                it != C.TIME_UNSET
        },
        player.isPlaying,
        player.playbackState == Player.STATE_BUFFERING,
        player.playerError?.let {
            "播放失败，请重试或切换清晰度"
        }
    )
    override fun release() {
        callback = null
        session.release()
        player.release()
    }
}
