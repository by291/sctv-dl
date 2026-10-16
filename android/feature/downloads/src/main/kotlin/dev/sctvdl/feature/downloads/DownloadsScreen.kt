package dev.sctvdl.feature.downloads

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.components.PrimaryTopAppBar
import dev.sctvdl.design.components.StatePanel
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.feature.downloads.components.DownloadCard

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DownloadsScreen(
    state: DownloadsUiState,
    onTab: (DownloadTab) -> Unit,
    onCancel: (String) -> Unit,
    onRetry: (String) -> Unit,
    onRemove: (String) -> Unit,
    onPlay: (String) -> Unit,
    onShare: (DownloadTask) -> Unit,
    onOpenFile: (DownloadTask) -> Unit,
    onSystemDownloads: () -> Unit
) {
    Column(Modifier.fillMaxSize()) {
        PrimaryTopAppBar(title = {
            Text("下载")
        }, actions = {
            IconButton(onClick = onSystemDownloads) { Icon(Icons.Outlined.FolderOpen, "系统下载") }
        })
        PrimaryTabRow(selectedTabIndex = state.tab.ordinal) {
            DownloadTab.entries.forEach { tab ->
                val count = state.tasks.count { it.state.isInActiveSection == (tab == DownloadTab.Active) }
                Tab(
                    selected = tab == state.tab,
                    unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    onClick = {
                        onTab(tab)
                    },
                    text = { Text("${if (tab == DownloadTab.Active) "进行中" else "下载记录"} · $count") }
                )
            }
        }
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            item {
                Text(
                    "文件保存在 Downloads/sctv-dl。退出应用后，系统会继续下载。",
                    Modifier.widthIn(max = 840.dp).fillMaxWidth(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            when {
                state.loading -> item { StatePanel("读取下载任务", "正在恢复系统下载状态", loading = true) }
                state.visible.isEmpty() -> item {
                    StatePanel(
                        if (state.tab == DownloadTab.Active) {
                            "还没有下载任务"
                        } else {
                            "还没有下载记录"
                        },
                        if (state.tab == DownloadTab.Active) {
                            "进入节目单，选择一集或批量保存喜欢的节目。"
                        } else {
                            "下载完成后，可以在这里离线观看和分享。"
                        }
                    )
                }
            }
            items(state.visible, key = {
                it.id
            }) { task ->
                DownloadCard(task, onCancel, onRetry, onRemove, onPlay, onShare, onOpenFile)
            }
        }
    }
}
