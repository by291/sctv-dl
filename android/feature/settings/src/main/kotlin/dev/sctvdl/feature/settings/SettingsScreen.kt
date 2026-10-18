package dev.sctvdl.feature.settings

import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.components.PrimaryTopAppBar
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.feature.settings.components.PreferenceContent
import dev.sctvdl.feature.settings.components.PreferenceGroup
import dev.sctvdl.feature.settings.components.SettingSwitch
import dev.sctvdl.ui.feedback.CachedErrorBanner

@Composable
internal fun SettingsScreen(
    settings: AppSettings,
    onTheme: (ThemeMode) -> Unit,
    onDynamic: (Boolean) -> Unit,
    onQuality: (Quality) -> Unit,
    onWifi: (Boolean) -> Unit,
    maintenance: StorageSettingsState = StorageSettingsState(),
    onClearCache: () -> Unit = {},
    onClearHistory: () -> Unit = {},
    error: AppError? = null,
    onRetry: () -> Unit = {}
) {
    var confirmation by rememberSaveable { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val versionName = remember(context) {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName.orEmpty()
    }

    Column(Modifier.fillMaxSize()) {
        PrimaryTopAppBar(title = { Text("设置") })
        LazyColumn(
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            error?.let {
                item(key = "settings-error") {
                    CachedErrorBanner(it, false, onRetry, retryLabel = "重试")
                }
            }
            item(key = "appearance") {
                PreferenceGroup("外观") {
                    PreferenceContent {
                        Text("显示模式", style = MaterialTheme.typography.bodyLarge)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ThemeMode.entries.forEach { mode ->
                                FilterChip(selected = settings.theme == mode, onClick = { onTheme(mode) }, label = {
                                    Text(
                                        when (mode) {
                                            ThemeMode.System -> "跟随系统"
                                            ThemeMode.Light -> "浅色"
                                            ThemeMode.Dark -> "深色"
                                        }
                                    )
                                })
                            }
                        }
                    }
                    SettingSwitch(
                        "动态配色",
                        "使用系统壁纸颜色",
                        settings.dynamicColour,
                        onDynamic,
                        Build.VERSION.SDK_INT >= 31
                    )
                }
            }
            item(key = "playback") {
                PreferenceGroup("播放") {
                    PreferenceContent {
                        Text("默认播放清晰度", style = MaterialTheme.typography.bodyLarge)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Quality.entries.forEach { quality ->
                                FilterChip(
                                    selected = settings.initialQuality == quality,
                                    onClick = { onQuality(quality) },
                                    label = { Text(quality.label) }
                                )
                            }
                        }
                    }
                }
            }
            item(key = "downloads") {
                PreferenceGroup("下载") {
                    SettingSwitch("仅 Wi-Fi 下载", "适用于之后创建的下载任务", settings.wifiOnlyDownloads, onWifi)
                    Text(
                        "文件保存在 Downloads/sctv-dl，可通过系统文件管理器访问。",
                        modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            item(key = "storage") {
                PreferenceGroup("存储与记录") {
                    TextButton(onClick = { confirmation = "cache" }, enabled = !maintenance.busy) { Text("清理缓存") }
                    TextButton(onClick = { confirmation = "history" }, enabled = !maintenance.busy) { Text("清空观看记录") }
                    maintenance.message?.let {
                        Text(it, Modifier.padding(16.dp), style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
            item(key = "about") {
                PreferenceGroup("关于") {
                    PreferenceContent {
                        Text("蜀台回看", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "sctv-dl · $versionName",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(Modifier.height(8.dp))
                        Text("浏览四川广播电视台节目，回看往期内容。", style = MaterialTheme.typography.bodyMedium)
                        Text(
                            "节目与图片来自公开节目服务。收藏和设置保存在本机。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
    confirmation?.let { action ->
        AlertDialog(
            onDismissRequest = { confirmation = null },
            title = { Text(if (action == "cache") "清理缓存？" else "清空观看记录？") },
            text = { Text(if (action == "cache") "清理节目和图片缓存，收藏、观看记录与下载视频会保留。" else "移除所有观看记录和续播位置，下载视频会保留。") },
            confirmButton = {
                TextButton(onClick = {
                    confirmation = null
                    if (action == "cache") onClearCache() else onClearHistory()
                }) { Text("确认清理") }
            },
            dismissButton = { TextButton(onClick = { confirmation = null }) { Text("取消") } }
        )
    }
}
