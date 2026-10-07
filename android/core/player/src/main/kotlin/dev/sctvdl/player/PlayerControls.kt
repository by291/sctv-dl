package dev.sctvdl.player

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Fullscreen
import androidx.compose.material.icons.outlined.FullscreenExit
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PictureInPictureAlt
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

@Composable
fun PlayerControls(
    state: PlaybackState,
    onPlay: () -> Unit,
    onSeek: (Long) -> Unit,
    onQuality: (dev.sctvdl.domain.Quality) -> Unit,
    onSpeed: (Float) -> Unit,
    fullscreen: Boolean,
    onFullscreen: () -> Unit,
    onPip: () -> Unit
) {
    var dragging by remember { mutableStateOf(false) }
    var progress by remember { mutableFloatStateOf(0f) }
    var speedMenu by remember { mutableStateOf(false) }
    var qualityMenu by remember { mutableStateOf(false) }
    val duration = state.durationMs ?: 0
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Slider(
            value = if (dragging) {
                progress
            } else if (duration > 0) {
                (state.positionMs.toFloat() / duration).coerceIn(0f, 1f)
            } else {
                0f
            },
            onValueChange = {
                dragging = true
                progress = it
            },
            onValueChangeFinished = {
                onSeek(
                    (
                        progress *
                            duration
                        ).toLong()
                )
                dragging = false
            },
            enabled = duration > 0,
            modifier = Modifier.semantics { contentDescription = "播放进度" }
        )
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onPlay) {
                Icon(
                    if (state.playWhenReady) Icons.Outlined.Pause else Icons.Outlined.PlayArrow,
                    if (state.playWhenReady) "暂停播放" else "开始播放"
                )
            }
            Text(
                "${timeLabel(state.positionMs)} / ${state.durationMs?.let(::timeLabel) ?: "--:--"}",
                Modifier.weight(1f),
                style = MaterialTheme.typography.labelMedium
            )
            IconButton(onClick = onFullscreen) {
                Icon(
                    if (fullscreen) Icons.Outlined.FullscreenExit else Icons.Outlined.Fullscreen,
                    if (fullscreen) "退出全屏" else "全屏播放"
                )
            }
            IconButton(onClick = onPip) { Icon(Icons.Outlined.PictureInPictureAlt, "进入画中画") }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box {
                TextButton(onClick = {
                    speedMenu = true
                }) { Text("${state.speed.toString().removeSuffix(".0")}× 速度") }
                DropdownMenu(speedMenu, { speedMenu = false }) {
                    listOf(0.75f, 1f, 1.25f, 1.5f, 2f).forEach { speed ->
                        DropdownMenuItem(text = { Text("$speed×") }, onClick = {
                            onSpeed(speed)
                            speedMenu = false
                        })
                    }
                }
            }
            if (state.variants.isNotEmpty()) {
                Box {
                    TextButton(onClick = {
                        qualityMenu = true
                    }, enabled = state.variants.size > 1) {
                        Text("${state.quality?.label ?: "本地"} 清晰度")
                    }
                    DropdownMenu(qualityMenu, { qualityMenu = false }) {
                        state.variants.forEach { variant ->
                            DropdownMenuItem(text = { Text(variant.quality.label) }, onClick = {
                                onQuality(variant.quality)
                                qualityMenu = false
                            })
                        }
                    }
                }
            }
        }
    }
}

private fun timeLabel(milliseconds: Long): String {
    val seconds = (milliseconds / 1000).coerceAtLeast(0)
    return if (seconds >= 3600) {
        "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
    } else {
        "%d:%02d".format(seconds / 60, seconds % 60)
    }
}
