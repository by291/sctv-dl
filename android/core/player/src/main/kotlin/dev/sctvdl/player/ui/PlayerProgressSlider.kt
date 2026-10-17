@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.player.ui

import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import androidx.media3.ui.compose.indicators.ProgressIndicator

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PlayerProgressSlider(
    state: dev.sctvdl.player.model.PlaybackState,
    onSeek: (Long) -> Unit,
    interactionSource: MutableInteractionSource,
    onInteraction: () -> Unit,
    modifier: Modifier = Modifier
) {
    var seeking by remember { mutableStateOf(false) }
    var seekPosition by remember { mutableFloatStateOf(0f) }
    val duration = state.durationMs
    val enabled = duration != null && duration > 0
    val colors = SliderDefaults.colors(
        inactiveTrackColor = Color.White.copy(alpha = 0.3f),
        disabledInactiveTrackColor = Color.White.copy(alpha = 0.15f)
    )

    Slider(
        value = if (seeking) {
            seekPosition
        } else if (enabled) {
            (state.positionMs.toDouble() / duration).toFloat().coerceIn(0f, 1f)
        } else {
            0f
        },
        onValueChange = {
            seeking = true
            seekPosition = it
            onInteraction()
        },
        onValueChangeFinished = {
            duration?.let { onSeek((seekPosition * it).toLong()) }
            seeking = false
            onInteraction()
        },
        modifier = modifier,
        enabled = enabled,
        colors = colors,
        interactionSource = interactionSource,
        track = { slider ->
            SliderDefaults.Track(
                sliderState = slider,
                enabled = enabled,
                colors = colors,
                thumbTrackGapSize = 0.dp,
                drawStopIndicator = null
            )
        }
    )
}
