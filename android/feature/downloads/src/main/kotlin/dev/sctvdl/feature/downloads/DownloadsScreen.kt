package dev.sctvdl.feature.downloads

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.components.PrimaryTopAppBar
import dev.sctvdl.design.components.StatePanel
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.supportedActions
import dev.sctvdl.domain.download.target
import dev.sctvdl.feature.downloads.components.DownloadCard

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
    val act: (DownloadAction, List<DownloadTarget>) -> Unit = { action, targets ->
        if (action in
            setOf(DownloadAction.Cancel, DownloadAction.DeleteFile, DownloadAction.RemoveRecord)
        ) {
            confirmation =
                action to targets
        } else {
            onAction(action, targets)
        }
    }
    BackHandler(state.selecting) { onExitSelection() }

    Column(Modifier.fillMaxSize()) {
        PrimaryTopAppBar(title = { Text(if (state.selecting) "已选 ${state.selection.size} 项" else "下载") }, actions = {
            TextButton(onClick = if (state.selecting) onExitSelection else onBeginSelection, enabled = !state.busy) {
                Text(if (state.selecting) "完成" else "批量管理")
            }
            IconButton(onClick = onSystemDownloads) { Icon(Icons.Outlined.FolderOpen, "系统下载") }
        })
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            DownloadFilter.entries.forEach { filter ->
                FilterChip(
                    selected = state.tab == filter,
                    onClick = { onTab(filter) },
                    enabled = !state.busy,
                    label = { Text("${filter.label} · ${state.tasks.count(filter::includes)}") }
                )
            }
        }
        if (state.selecting) {
            val supported = state.tasks.filter { it.id in state.selection }.flatMap { supportedActions(it) }.toSet()
            FlowRow(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(onClick = onSelectAll, enabled = !state.busy) { Text("全选当前列表") }
                DownloadAction.entries.filter { it in supported }.forEach { action ->
                    TextButton(onClick = { act(action, state.targets) }, enabled = !state.busy) { Text(action.label) }
                }
            }
        }
        LazyColumn(
            Modifier.fillMaxSize(),
            state = lists[state.tab.ordinal],
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            when {
                state.loading -> item { StatePanel("读取下载任务", "正在恢复下载状态", loading = true) }
                state.error != null -> item { StatePanel("暂时无法读取", state.error, onRetry = onReload) }
                state.visible.isEmpty() -> item { StatePanel("暂无${state.tab.label}任务", "进入节目单，选择一集或批量保存喜欢的节目。") }
            }
            items(state.visible, key = { it.id }) { task ->
                DownloadCard(
                    task, onPlay, onShare, onOpenFile, { action -> act(action, listOf(task.target)) },
                    state.selecting, task.id in state.selection, { onToggle(task) }, state.busy
                )
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
