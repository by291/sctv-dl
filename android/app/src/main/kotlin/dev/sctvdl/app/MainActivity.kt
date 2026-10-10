package dev.sctvdl.app

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Bundle
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowInsetsControllerCompat
import dagger.hilt.android.AndroidEntryPoint
import dev.sctvdl.player.media3.PlayerSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    private var playerSession: PlayerSession? = null
    private val mutablePip = MutableStateFlow(false)
    val pictureInPicture = mutablePip.asStateFlow()
    private val mutableDownloadsRequest = MutableStateFlow(0)
    val downloadsRequest = mutableDownloadsRequest.asStateFlow()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleIntent(intent)
        setContent { SctvApp(this) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("open_downloads", false) == true) {
            mutableDownloadsRequest.value++
            // Recreation restores the current route instead of replaying the original notification.
            intent.removeExtra("open_downloads")
        }
    }

    fun setSystemBarIcons(darkIcons: Boolean) {
        WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = darkIcons
            isAppearanceLightNavigationBars = darkIcons
        }
    }

    fun bindPlayer(session: PlayerSession) {
        playerSession = session
    }
    fun unbindPlayer(session: PlayerSession) {
        if (playerSession === session) playerSession = null
    }
    fun pausePlayerForDismissal() {
        playerSession?.controller?.pauseForDismissal()
    }

    fun enterPlayerPictureInPicture(): Boolean {
        if (playerSession == null ||
            !packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            return false
        }
        return enterPictureInPictureMode(
            PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
        )
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        mutablePip.value = isInPictureInPictureMode
    }

    override fun onStop() {
        playerSession?.controller?.onBackground(isInPictureInPictureMode)
        super.onStop()
    }
}
