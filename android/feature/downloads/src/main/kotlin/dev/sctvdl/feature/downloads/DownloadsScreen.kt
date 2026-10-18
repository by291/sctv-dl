package dev.sctvdl.feature.downloads

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Deselect
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.SelectAll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.components.PrimaryTopAppBar
import dev.sctvdl.design.components.StatePanel
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.target
import dev.sctvdl.feature.downloads.components.DownloadCard
import dev.sctvdl.feature.downloads.components.DownloadSelectionBar

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
    onSystemDownloads: () -> Unit,
    onBeginSelection: () -> Unit = {},
    onExitSelection: () -> Unit = {},
    onSelectAll: () -> Unit = {},
    onToggle: (DownloadTask) -> Unit = {},
    onReload: () -> Unit = {},
    onAction: (DownloadAction, List<DownloadTarget>) -> Unit = { action, targets ->
        targets.forEach {
            when (action) {
                DownloadAction.Cancel -> onCancel(it.id)
                DownloadAction.Retry -> onRetry(it.id)
                DownloadAction.RemoveRecord -> onRemove(it.id)
                else -> Unit
            }
        }
    }
) {
    val lists = DownloadFilter.entries.map { rememberLazyListState() }
    var confirmation by remember { mutableStateOf<Pair<DownloadAction, List<DownloadTarget>>?>(null) }
    val ready = !state.loading && state.error == null
    val blocked = state.busy || confirmation != null
    val visible = state.visible
    val selectedCount = visible.count { it.id in state.selection }
    val allSelected = visible.isNotEmpty() && selectedCount == visible.size
    val act: (DownloadAction, List<DownloadTarget>) -> Unit = { action, targets ->
        if (action in setOf(DownloadAction.Cancel, DownloadAction.DeleteFile, DownloadAction.RemoveRecord)) {
            // Keep the selected attempt identities while the repository continues to emit newer snapshots.
            confirmation = action to targets
        } else {
            onAction(action, targets)
        }
    }

    BackHandler(state.selecting) { if (!blocked) onExitSelection() }

    Column(Modifier.fillMaxSize()) {
        PrimaryTopAppBar(
            title = { Text(if (state.selecting) "已选择 $selectedCount 项" else "下载") },
            navigationIcon = {
                if (state.selecting) {
                    IconButton(onClick = onExitSelection, enabled = !blocked) {
                        Icon(Icons.Outlined.Close, "退出批量管理")
                    }
                }
            },
            actions = {
                if (!state.selecting) {
                    IconButton(onClick = onBeginSelection, enabled = ready && state.tasks.isNotEmpty() && !blocked) {
                        Icon(Icons.Outlined.Checklist, "批量管理")
                    }
                    IconButton(onClick = onSystemDownloads) { Icon(Icons.Outlined.FolderOpen, "系统下载") }
                }
            }
        )
        Column(Modifier.weight(1f).widthIn(max = 720.dp).fillMaxWidth().align(Alignment.CenterHorizontally)) {
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                DownloadFilter.entries.forEach { filter ->
                    FilterChip(
                        selected = state.tab == filter,
                        onClick = { onTab(filter) },
                        enabled = !blocked,
                        label = { Text("${filter.label} ${state.tasks.count(filter::includes)}") }
                    )
                }
            }
            if (state.selecting) {
                TextButton(
                    onClick = onSelectAll,
                    enabled = ready && visible.isNotEmpty() && !blocked,
                    modifier = Modifier.padding(horizontal = 12.dp)
                ) {
                    Icon(
                        if (allSelected) Icons.Outlined.Deselect else Icons.Outlined.SelectAll,
                        null,
                        Modifier.size(18.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(if (allSelected) "取消全选" else "全选当前列表")
                }
            }
            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth().testTag("download-list"),
                state = lists[state.tab.ordinal],
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                when {
                    state.loading -> item { StatePanel("读取下载任务", "正在恢复下载状态", loading = true) }
                    state.error != null -> item {
                        StatePanel("无法读取下载记录", state.error, onRetry = onReload, icon = Icons.Outlined.CloudOff)
                    }
                    visible.isEmpty() -> item {
                        val empty = state.tasks.isEmpty() && state.tab == DownloadFilter.All
                        StatePanel(
                            if (empty) "还没有下载任务" else "没有符合筛选的任务",
                            if (empty) "在节目回看中选择视频下载，随时离线观看。" else "可以切换其他筛选查看下载记录。",
                            icon = Icons.Outlined.Download
                        )
                    }
                    else -> DownloadFilter.entries.filter { it != DownloadFilter.All }.forEach { section ->
                        val tasks = visible.filter(section::includes)
                        if (tasks.isNotEmpty()) {
                            item(key = "section-${section.name}") {
                                Text(
                                    "${section.sectionTitle} · ${tasks.size}",
                                    modifier = Modifier.padding(start = 4.dp, top = 12.dp),
                                    style = MaterialTheme.typography.labelLarge,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            items(tasks, key = { it.id }) { task ->
                                DownloadCard(
                                    task = task,
                                    onPlay = onPlay,
                                    onShare = onShare,
                                    onOpenFile = onOpenFile,
                                    onAction = { action -> act(action, listOf(task.target)) },
                                    selecting = state.selecting,
                                    selected = task.id in state.selection,
                                    onToggle = { onToggle(task) },
                                    busy = blocked,
                                    onLongPress = {
                                        onBeginSelection()
                                        onToggle(task)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            if (state.selecting) {
                DownloadSelectionBar(state, enabled = ready && !blocked, onAction = act)
            }
        }
    }
    confirmation?.let { (action, targets) ->
        AlertDialog(
            onDismissRequest = { confirmation = null },
            title = { Text("${action.label} ${targets.size} 项？") },
            text = {
                Text(
                    when (action) {
                        DownloadAction.DeleteFile -> "删除已下载的视频文件，下载记录会保留。"
                        DownloadAction.RemoveRecord -> "只移除下载记录，公共目录中的视频文件会保留。"
                        else -> "停止所选任务并清理未完成的临时文件。"
                    }
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmation = null
                    onAction(action, targets)
                }) { Text("确认${action.label}") }
            },
            dismissButton = { TextButton(onClick = { confirmation = null }) { Text("取消") } }
        )
    }
}

private val DownloadFilter.sectionTitle: String get() = when (this) {
    DownloadFilter.Removed -> "已移除"
    else -> label
}
