package dev.sctvdl.app.platform

import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.media.AudioManager
import android.provider.Settings
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import dev.sctvdl.app.MainActivity
import dev.sctvdl.feature.player.PlaybackHost
import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.player.ui.PlayerGestureEnvironment

class ActivityPlaybackHost(private val activity: MainActivity) : PlaybackHost {
    override val gestureEnvironment = object : PlayerGestureEnvironment {
        private var enteringBrightness: Float? = null
        private var volumeRemainder = 0f
        private var lastVolume: Int? = null

        override fun captureBrightness() {
            if (enteringBrightness == null) enteringBrightness = activity.window.attributes.screenBrightness
        }

        override fun adjustBrightness(delta: Float): Int {
            val attributes = activity.window.attributes
            if (enteringBrightness == null) enteringBrightness = attributes.screenBrightness
            val current = attributes.screenBrightness.takeIf { it >= 0f } ?: (
                Settings.System.getInt(
                    activity.contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS,
                    128
                ) / 255f
                )
            attributes.screenBrightness = (current + delta).coerceIn(0f, 1f)
            activity.window.attributes = attributes
            return (attributes.screenBrightness * 100).toInt()
        }

        override fun adjustVolume(delta: Float): Int {
            val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val current = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
            // Re-read the native level for every move; physical key changes win over our fractional remainder.
            if (lastVolume != current) volumeRemainder = 0f
            val adjustment = delta * maximum + volumeRemainder
            val steps = adjustment.toInt()
            volumeRemainder = adjustment - steps
            val next = (current + steps).coerceIn(0, maximum)
            lastVolume = next
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, next, 0)
            return if (maximum > 0) next * 100 / maximum else 0
        }

        override fun restoreBrightness() {
            val brightness = enteringBrightness ?: return
            activity.window.attributes = activity.window.attributes.apply { screenBrightness = brightness }
            enteringBrightness = null
        }

        override fun needsGestureHint(): Boolean = !activity.getSharedPreferences(
            "player_gestures",
            Context.MODE_PRIVATE
        ).getBoolean("fullscreen_hint_seen", false)

        override fun acknowledgeGestureHint() {
            activity.getSharedPreferences("player_gestures", Context.MODE_PRIVATE)
                .edit().putBoolean("fullscreen_hint_seen", true).apply()
        }
    }

    override val pictureInPicture = activity.pictureInPicture
    override val supportsPictureInPicture = activity.packageManager.hasSystemFeature(
        PackageManager.FEATURE_PICTURE_IN_PICTURE
    )

    override fun bindPlayer(session: PlayerSession) = activity.bindPlayer(session)

    override fun unbindPlayer(session: PlayerSession) = activity.unbindPlayer(session)

    override fun enterPictureInPicture() = activity.enterPlayerPictureInPicture()

    override fun fullscreen(enabled: Boolean) {
        val controller = WindowCompat.getInsetsController(
            activity.window,
            activity.window.decorView
        )
        if (enabled) {
            gestureEnvironment.captureBrightness()
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            gestureEnvironment.restoreBrightness()
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            controller.show(WindowInsetsCompat.Type.systemBars())
        }
    }
}
