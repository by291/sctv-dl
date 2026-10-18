@file:androidx.annotation.OptIn(
    androidx.media3.common.util.UnstableApi::class,
    androidx.media3.common.util.ExperimentalApi::class
)

package dev.sctvdl.player.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Fullscreen
import androidx.compose.material.icons.outlined.FullscreenExit
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import androidx.media3.ui.compose.material3.buttons.PlayPauseButton
import androidx.media3.ui.compose.material3.indicator.DurationText
import androidx.media3.ui.compose.material3.indicator.PositionText
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.player.model.PlaybackState

@Composable
internal fun PlayerControls(
    state: PlaybackState,
    onTogglePlay: () -> Unit,
    onSeek: (Long) -> Unit,
    onQuality: (Quality) -> Unit,
    onSpeed: (Float) -> Unit,
    fullscreen: Boolean,
    onFullscreen: () -> Unit,
    onInteraction: () -> Unit,
    onInteractingChanged: (Boolean) -> Unit,
    menuMaxHeight: Dp
) {
    val speedOptions = remember {
        listOf(0.75f, 1f, 1.25f, 1.5f, 2f).associateWith { "${it.toString().removeSuffix(".0")}×" }
    }
    val labelStyle = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum")
    val textMeasurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val controlSize = 48.dp
    // Reserve each widest label so elapsed time and menu changes do not move adjacent controls.
    val speedControlWidth = remember(speedOptions, labelStyle, textMeasurer, density) {
        val labelWidth = speedOptions.values.maxOf { textMeasurer.measure(it, labelStyle).size.width }
        (with(density) { labelWidth.toDp() } + 8.dp).coerceAtLeast(controlSize)
    }

    val seekInteraction = remember { MutableInteractionSource() }
    val dragging by seekInteraction.collectIsDraggedAsState()
    val pressing by seekInteraction.collectIsPressedAsState()
    val rowScroll = rememberScrollState()
    var speedMenu by remember { mutableStateOf(false) }
    var qualityMenu by remember { mutableStateOf(false) }

    LaunchedEffect(dragging, pressing, speedMenu, qualityMenu, rowScroll.isScrollInProgress) {
        onInteractingChanged(dragging || pressing || speedMenu || qualityMenu || rowScroll.isScrollInProgress)
    }

    val timeStyle = labelStyle
    val timeWidth = with(density) { textMeasurer.measure("00:00:00", timeStyle).size.width.toDp() } + 4.dp
    val qualityLabels = state.variants.map { it.quality.label } + "画质"
    val qualityWidth = (
        with(density) {
            qualityLabels.maxOf { textMeasurer.measure(it, labelStyle).size.width }.toDp()
        } + 8.dp
        ).coerceAtLeast(controlSize)
    val rowMinimum = 48.dp + controlSize + timeWidth * 2 + speedControlWidth + 64.dp +
        if (state.variants.isNotEmpty()) qualityWidth else 0.dp

    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val rowWidth = maxOf(maxWidth, rowMinimum)
        Row(
            Modifier.horizontalScroll(rowScroll).width(rowWidth).heightIn(min = 48.dp)
                .semantics { contentDescription = "播放控制栏" },
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(
                onClick = {
                    onTogglePlay()
                    onInteraction()
                },
                modifier = Modifier.size(48.dp).semantics {
                    contentDescription = if (state.playWhenReady && !state.ended) "暂停播放" else "开始播放"
                }
            ) {
                Icon(
                    if (state.playWhenReady && !state.ended) Icons.Outlined.Pause else Icons.Outlined.PlayArrow,
                    null,
                    tint = Color.White
                )
            }
            Text(
                playbackTime(state.positionMs),
                Modifier.width(timeWidth),
                color = Color.White,
                style = timeStyle,
                textAlign = TextAlign.Center,
                maxLines = 1
            )
            PlayerProgressSlider(
                state = state,
                onSeek = onSeek,
                modifier = Modifier.weight(1f).semantics { contentDescription = "播放进度" },
                interactionSource = seekInteraction,
                onInteraction = onInteraction
            )
            Text(
                playbackTime(state.durationMs),
                Modifier.width(timeWidth),
                color = Color.White,
                style = timeStyle,
                textAlign = TextAlign.Center,
                maxLines = 1
            )
            Box {
                PlayerMenuButton(
                    "${state.speed.toString().removeSuffix(".0")}×",
                    "播放速度",
                    true,
                    modifier = Modifier.width(speedControlWidth).height(controlSize)
                ) {
                    onInteraction()
                    speedMenu = true
                }
                PlayerChoiceMenu(speedMenu, {
                    speedMenu = false
                    onInteraction()
                }, menuMaxHeight) {
                    speedOptions.forEach { (speed, label) ->
                        PlayerChoiceMenuItem(
                            label = label,
                            selected = speed == state.speed,
                            onClick = {
                                onSpeed(speed)
                                speedMenu = false
                                onInteraction()
                            }
                        )
                    }
                }
            }
            if (state.variants.isNotEmpty()) {
                Box {
                    PlayerMenuButton(
                        state.quality?.label ?: "画质",
                        "清晰度",
                        true,
                        modifier = Modifier.width(qualityWidth).height(controlSize)
                    ) {
                        onInteraction()
                        qualityMenu = true
                    }
                    PlayerChoiceMenu(qualityMenu, {
                        qualityMenu = false
                        onInteraction()
                    }, menuMaxHeight) {
                        state.variants.forEach { variant ->
                            PlayerChoiceMenuItem(
                                label = variant.quality.label,
                                selected = variant.quality == state.quality,
                                onClick = {
                                    if (variant.quality != state.quality) onQuality(variant.quality)
                                    qualityMenu = false
                                    onInteraction()
                                }
                            )
                        }
                    }
                }
            }
            IconButton(
                onClick = {
                    onInteraction()
                    onFullscreen()
                },
                modifier = Modifier.size(controlSize).semantics {
                    contentDescription = if (fullscreen) "退出全屏" else "全屏播放"
                }
            ) {
                Icon(
                    if (fullscreen) Icons.Outlined.FullscreenExit else Icons.Outlined.Fullscreen,
                    null,
                    tint = Color.White
                )
            }
        }
    }
}

@Composable
private fun PlayerMenuButton(
    label: String,
    description: String,
    switchable: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    TextButton(
        onClick = onClick,
        enabled = switchable,
        modifier = modifier.semantics { contentDescription = description },
        contentPadding = PaddingValues(horizontal = 4.dp),
        colors = ButtonDefaults.textButtonColors(contentColor = Color.White, disabledContentColor = Color.White)
    ) {
        Text(label, style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum"), maxLines = 1)
    }
}
