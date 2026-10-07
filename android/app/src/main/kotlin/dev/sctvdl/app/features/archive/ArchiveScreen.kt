package dev.sctvdl.app.features.archive

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.ContentCard
import dev.sctvdl.design.ErrorBanner
import dev.sctvdl.design.QualitySheet
import dev.sctvdl.design.StatePanel
import dev.sctvdl.design.TouchTarget
import dev.sctvdl.domain.BroadcastDate
import dev.sctvdl.domain.DownloadRequest
import dev.sctvdl.domain.ProgrammeContent
import dev.sctvdl.domain.videoVariants

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArchiveScreen(
    state: ArchiveUiState,
    wifiOnly: Boolean,
    onBack: () -> Unit,
    onDate: (BroadcastDate) -> Unit,
    onRefresh: () -> Unit,
    onFavourite: () -> Unit,
    onPlay: (ProgrammeContent) -> Unit,
    onBeginSelection: () -> Unit,
    onSelectAll: () -> Unit,
    onSelectFull: () -> Unit,
    onToggle: (String) -> Unit,
    onExitSelection: () -> Unit,
    onDownload: (List<DownloadRequest>) -> Unit
) {
    var showDates by rememberSaveable { mutableStateOf(false) }
    var downloadIds by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
    BackHandler(state.selectionMode) { onExitSelection() }
    LaunchedEffect(state.programmeId, state.date?.id) {
        downloadIds = arrayListOf()
        showDates = false
    }

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = {
                Text(
                    state.programme?.name ?: "往期节目",
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            },
            navigationIcon = {
                IconButton(onClick = if (state.selectionMode) onExitSelection else onBack) {
                    Icon(
                        Icons.AutoMirrored.Outlined.ArrowBack,
                        "返回"
                    )
                }
            },
            actions = {
                IconButton(onClick = onFavourite) {
                    Icon(
                        if (state.favourite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                        if (state.favourite) "取消收藏栏目" else "收藏栏目"
                    )
                }
                IconButton(
                    onClick = onRefresh,
                    enabled = !state.dates.isRefreshing && !state.contents.isRefreshing
                ) {
                    Icon(
                        Icons.Outlined.Refresh,
                        "刷新节目"
                    )
                }
            }
        )
        if (state.selectionMode) {
            FlowRow(
                Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                TextButton(onClick = onSelectAll) { Text("全选") }
                TextButton(onClick = onSelectFull) { Text("仅完整节目") }
                TextButton(onClick = onExitSelection) { Text("退出选择") }
            }
        }
        LazyColumn(
            Modifier.weight(1f),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                Surface(
                    color = MaterialTheme.colorScheme.surfaceContainer,
                    shape = MaterialTheme.shapes.large
                ) {
                    Column(
                        Modifier.fillMaxWidth().padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text("按日期回看", style = MaterialTheme.typography.titleLarge)
                        Text(
                            "从完整节目到每一条片段",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        FilledTonalButton(
                            onClick = { showDates = true },
                            enabled = state.dates.data.orEmpty().isNotEmpty(),
                            modifier = Modifier.fillMaxWidth().heightIn(min = TouchTarget)
                        ) {
                            Icon(Icons.Outlined.CalendarMonth, null)
                            Spacer(Modifier.width(8.dp))
                            Text(state.date?.date?.toString() ?: "选择播出日期")
                        }
                    }
                }
            }
            state.dates.error?.let { error ->
                item {
                    ErrorBanner(
                        error,
                        state.dates.data != null,
                        onRefresh
                    )
                }
            }
            state.contents.error?.let { error ->
                item {
                    ErrorBanner(
                        error,
                        state.contents.data != null,
                        onRefresh
                    )
                }
            }
            when {
                state.dates.data == null && state.dates.error == null -> item {
                    StatePanel(
                        "加载播出日期",
                        "正在查询往期节目",
                        loading = true
                    )
                }
                state.dates.data?.isEmpty() == true -> item {
                    StatePanel(
                        "暂无播出日期",
                        "该栏目暂时没有可回看的节目",
                        onRetry = onRefresh
                    )
                }
                state.date != null && state.contents.data == null && state.contents.error == null -> item {
                    StatePanel(
                        "加载节目",
                        "正在获取当期节目单",
                        loading = true
                    )
                }
                state.contents.data?.isEmpty() == true -> item {
                    StatePanel(
                        "这一天暂无节目",
                        "可以选择其他播出日期",
                        onRetry = onRefresh
                    )
                }
                else -> {
                    if (state.contents.isRefreshing) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                    items(
                        state.fullEpisodes,
                        key = { "full-${it.id}" }
                    ) { content ->
                        ContentCard(
                            content,
                            true,
                            state.selectionMode,
                            content.id in state.selectedIds,
                            { onPlay(content) },
                            { downloadIds = arrayListOf(content.id) },
                            { onToggle(content.id) }
                        )
                    }
                    if (state.clips.isNotEmpty()) {
                        item {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    "节目片段 · ${state.clips.size}",
                                    Modifier.weight(1f),
                                    style = MaterialTheme.typography.titleMedium
                                )
                                if (!state.selectionMode) TextButton(onClick = onBeginSelection) { Text("批量下载") }
                            }
                        }
                    }
                    items(
                        state.clips,
                        key = { it.id }
                    ) { content ->
                        ContentCard(
                            content,
                            false,
                            state.selectionMode,
                            content.id in state.selectedIds,
                            { onPlay(content) },
                            { downloadIds = arrayListOf(content.id) },
                            { onToggle(content.id) }
                        )
                    }
                    if (state.clips.isEmpty() && state.fullEpisodes.isNotEmpty() &&
                        !state.selectionMode
                    ) {
                        item { TextButton(onClick = onBeginSelection) { Text("批量下载") } }
                    }
                }
            }
        }
        if (state.selectionMode) {
            Surface(shadowElevation = 4.dp) {
                Row(
                    Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("已选 ${state.selectedIds.size} 个", Modifier.weight(1f))
                    Button(
                        onClick = { downloadIds = ArrayList(state.selectedIds) },
                        enabled = state.selectedIds.isNotEmpty()
                    ) { Text("下载所选") }
                }
            }
        }
    }
    if (showDates) {
        BroadcastDateSheet(
            state.dates.data.orEmpty(),
            state.date?.id,
            onDate,
            { showDates = false }
        )
    }
    if (downloadIds.isNotEmpty()) {
        val selected = state.contents.data.orEmpty().filter { it.id in downloadIds && videoVariants(it).isNotEmpty() }
        val variants = if (selected.size == 1) {
            videoVariants(selected.single())
        } else {
            selected.flatMap(::videoVariants).distinctBy { it.quality }
        }
        QualitySheet(variants, selected.size, { quality ->
            val date = state.date
            if (date != null) {
                onDownload(
                    selected.map {
                        DownloadRequest(
                            state.programme?.name ?: "节目",
                            date.date,
                            it,
                            quality,
                            wifiOnly
                        )
                    }
                )
            }
            downloadIds = arrayListOf()
        }, { downloadIds = arrayListOf() })
    }
}
