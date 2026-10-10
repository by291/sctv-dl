package dev.sctvdl.app.platform

import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import dev.sctvdl.app.MainActivity
import dev.sctvdl.feature.player.PlaybackHost
import dev.sctvdl.player.media3.PlayerSession

class ActivityPlaybackHost(private val activity: MainActivity) : PlaybackHost {
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
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            controller.show(WindowInsetsCompat.Type.systemBars())
        }
    }
}
