@file:androidx.annotation.OptIn(
    androidx.media3.common.util.UnstableApi::class,
    androidx.media3.common.util.ExperimentalApi::class
)

package dev.sctvdl.player

import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import androidx.media3.ui.compose.material3.buttons.PlayPauseButton
import androidx.media3.ui.compose.material3.indicator.DurationText
import androidx.media3.ui.compose.material3.indicator.PositionText
import dev.sctvdl.domain.Quality

@Composable
internal fun PlayerControls(
    player: Player,
    state: PlaybackState,
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
    val labelStyle = MaterialTheme.typography.labelLarge
    val textMeasurer = rememberTextMeasurer()
    val density = LocalDensity.current
    // Reserve the widest label, horizontal padding, and chevron so the popup anchor stays fixed.
    val speedControlWidth = remember(speedOptions, labelStyle, textMeasurer, density) {
        val labelWidth = speedOptions.values.maxOf { textMeasurer.measure(it, labelStyle).size.width }
        (with(density) { labelWidth.toDp() } + 36.dp).coerceAtLeast(64.dp)
    }

    val seekInteraction = remember { MutableInteractionSource() }
    val dragging by seekInteraction.collectIsDraggedAsState()
    val pressing by seekInteraction.collectIsPressedAsState()
    var speedMenu by remember { mutableStateOf(false) }
    var qualityMenu by remember { mutableStateOf(false) }

    LaunchedEffect(dragging, pressing, speedMenu, qualityMenu) {
        onInteractingChanged(dragging || pressing || speedMenu || qualityMenu)
    }

    Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            PositionText(player, color = Color.White)
            PlayerProgressSlider(
                player,
                modifier = Modifier.weight(1f).semantics { contentDescription = "播放进度" },
                interactionSource = seekInteraction,
                onInteraction = onInteraction
            )
            if (state.durationMs == null) {
                Text("--:--", color = Color.White, style = TextStyle(fontFeatureSettings = "tnum"))
            } else {
                DurationText(player, color = Color.White)
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            PlayPauseButton(
                player,
                imageVector = { if (showPlay) Icons.Outlined.PlayArrow else Icons.Outlined.Pause },
                contentDescription = { if (showPlay) "开始播放" else "暂停播放" },
                iconSize = 24.dp,
                tint = Color.White,
                onClick = {
                    this.onClick()
                    onInteraction()
                }
            )
            Spacer(Modifier.weight(1f))
            Box {
                PlayerMenuButton(
                    "${state.speed.toString().removeSuffix(".0")}×",
                    "播放速度",
                    true,
                    modifier = Modifier.width(speedControlWidth)
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
                        state.quality?.label ?: "清晰度",
                        "清晰度",
                        state.variants.size > 1
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
                                    onQuality(variant.quality)
                                    qualityMenu = false
                                    onInteraction()
                                }
                            )
                        }
                    }
                }
            }
            IconButton(onClick = {
                onInteraction()
                onFullscreen()
            }) {
                Icon(
                    if (fullscreen) Icons.Outlined.FullscreenExit else Icons.Outlined.Fullscreen,
                    if (fullscreen) "退出全屏" else "全屏播放",
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
        modifier = modifier.heightIn(min = 48.dp).semantics { contentDescription = description },
        contentPadding = PaddingValues(horizontal = 8.dp),
        colors = ButtonDefaults.textButtonColors(contentColor = Color.White, disabledContentColor = Color.White)
    ) {
        Text(label, style = MaterialTheme.typography.labelLarge, maxLines = 1)
        if (switchable) Icon(Icons.Outlined.ExpandMore, null, Modifier.padding(start = 4.dp).size(16.dp))
    }
}
