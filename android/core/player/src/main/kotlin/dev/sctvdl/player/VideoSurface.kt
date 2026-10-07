@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.player

import android.os.Build
import android.view.LayoutInflater
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import androidx.media3.ui.compose.ContentFrame

@Composable
fun VideoSurface(player: Player, modifier: Modifier = Modifier) {
    // Android 10's Compose external surfaces corrupt the window, especially across rotation (media#3285).
    // A native TextureView avoids that compositor path for the public non-DRM MP4 sources.
    if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
        AndroidView(
            factory = { context ->
                (LayoutInflater.from(context).inflate(R.layout.texture_player_surface, null) as PlayerView).apply {
                    this.player = player
                }
            },
            modifier = modifier,
            update = { it.player = player },
            onRelease = { it.player = null }
        )
    } else {
        ContentFrame(player = player, modifier = modifier)
    }
}
