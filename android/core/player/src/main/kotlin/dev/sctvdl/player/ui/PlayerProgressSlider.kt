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
    player: Player,
    interactionSource: MutableInteractionSource,
    onInteraction: () -> Unit,
    modifier: Modifier = Modifier
) {
    var widthPx by remember { mutableIntStateOf(0) }

    // Media3 owns progress updates and seeking; the native track only removes its default thumb gap.
    ProgressIndicator(player, totalTickCount = widthPx) {
        var seeking by remember(player) { mutableStateOf(false) }
        var seekPosition by remember(player) { mutableFloatStateOf(0f) }
        val colors = SliderDefaults.colors(
            inactiveTrackColor = Color.White.copy(alpha = 0.3f),
            disabledInactiveTrackColor = Color.White.copy(alpha = 0.15f)
        )

        Slider(
            value = if (seeking) seekPosition else currentPositionProgress,
            onValueChange = {
                seeking = true
                seekPosition = it
                onInteraction()
            },
            onValueChangeFinished = {
                updateCurrentPositionProgress(seekPosition)
                seeking = false
                onInteraction()
            },
            modifier = modifier.onSizeChanged { widthPx = it.width },
            enabled = changingProgressEnabled,
            colors = colors,
            interactionSource = interactionSource,
            track = { state ->
                SliderDefaults.Track(
                    sliderState = state,
                    enabled = changingProgressEnabled,
                    colors = colors,
                    thumbTrackGapSize = 0.dp,
                    drawStopIndicator = null
                )
            }
        )
    }
}
