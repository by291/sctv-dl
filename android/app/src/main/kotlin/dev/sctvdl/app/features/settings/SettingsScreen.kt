package dev.sctvdl.app.features.settings

import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.ThemeMode

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    settings: AppSettings,
    onTheme: (ThemeMode) -> Unit,
    onDynamic: (Boolean) -> Unit,
    onQuality: (Quality) -> Unit,
    onWifi: (Boolean) -> Unit
) {
    Column(Modifier.fillMaxSize()) {
        TopAppBar(title = { Text("设置") })
        LazyColumn(
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            item(key = "appearance") {
                PreferenceGroup("外观") {
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
            item(key = "downloads") {
                PreferenceGroup("下载") {
                    SettingSwitch("仅 Wi-Fi 下载", "适用于之后创建的下载任务", settings.wifiOnlyDownloads, onWifi)
                    Text(
                        "文件保存在 Downloads/sctv-dl，可通过系统文件管理器访问。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            item(key = "about") {
                PreferenceGroup("关于") {
                    Text("蜀台回看", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "sctv-dl · 0.1.0",
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

@Composable
private fun PreferenceGroup(title: String, content: @Composable () -> Unit) {
    Column(Modifier.widthIn(max = 720.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            title,
            Modifier.padding(start = 4.dp),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary
        )
        Surface(color = MaterialTheme.colorScheme.surfaceContainerLow, shape = MaterialTheme.shapes.medium) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                content()
            }
        }
    }
}

@Composable
private fun SettingSwitch(
    title: String,
    subtitle: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
    enabled: Boolean = true
) {
    Row(
        Modifier.fillMaxWidth().toggleable(checked, enabled = enabled, role = Role.Switch, onValueChange = onChange)
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(Modifier.weight(1f)) {
            Text(title)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Switch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}
