package dev.sctvdl.feature.programmes.archive

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.Sort
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.components.ContentUpdateAction
import dev.sctvdl.design.components.StatePanel
import dev.sctvdl.design.theme.TouchTarget
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.media.videoVariants
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.feature.programmes.archive.components.ArchiveContentPlaceholder
import dev.sctvdl.feature.programmes.archive.components.ArchiveHeader
import dev.sctvdl.feature.programmes.archive.components.ArchiveHeaderPlaceholder
import dev.sctvdl.feature.programmes.archive.components.BroadcastDates
import dev.sctvdl.feature.programmes.archive.components.BroadcastDatesPlaceholder
import dev.sctvdl.feature.programmes.archive.components.EpisodeCard
import dev.sctvdl.ui.downloads.DownloadQualitySheet
import dev.sctvdl.ui.feedback.CachedErrorBanner
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.launch

private val BroadcastDateLabel = DateTimeFormatter.ofPattern("yyyy年M月d日", Locale.SIMPLIFIED_CHINESE)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ArchiveScreen(
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
    onDownload: (List<DownloadRequest>) -> Unit,
    onApplyUpdates: () -> Unit = {},
    onToggleClipSort: () -> Unit = {}
) {
    var showDates by rememberSaveable { mutableStateOf(false) }
    var downloadIds by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
    val errors = listOfNotNull(state.dates.error, state.contents.error).distinctBy { it.message }
    val loadingDates = state.dates.data == null && state.dates.error == null
    val loadingContents = state.date != null && state.contents.data == null && state.contents.error == null
    val largeText = LocalDensity.current.fontScale >= 1.5f
    val scroll = rememberLazyListState()
    val scope = rememberCoroutineScope()
    BackHandler(state.selectionMode) { onExitSelection() }
    LaunchedEffect(state.programmeId, state.date?.id) {
        downloadIds = arrayListOf()
        showDates = false
    }

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text(if (state.selectionMode) "已选 ${state.selectedIds.size} 个" else "栏目详情") },
            navigationIcon = {
                IconButton(onClick = if (state.selectionMode) onExitSelection else onBack) {
                    Icon(
                        if (state.selectionMode) Icons.Outlined.Close else Icons.AutoMirrored.Outlined.ArrowBack,
                        if (state.selectionMode) "退出选择" else "返回"
                    )
                }
            },
            actions = {
                if (state.hasUpdate && !state.selectionMode) {
                    ContentUpdateAction(onUpdate = {
                        onApplyUpdates()
                        scope.launch { scroll.scrollToItem(0) }
                    })
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
            }
        }
        Column(Modifier.weight(1f).fillMaxWidth()) {
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                state = scroll,
                contentPadding = PaddingValues(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                if (!state.selectionMode) {
                    item(key = "programme") {
                        if (state.programme == null && loadingDates) {
                            ArchiveHeaderPlaceholder()
                        } else {
                            ArchiveHeader(state, onFavourite)
                        }
                    }
                    if (loadingDates) {
                        item(key = "dates") { BroadcastDatesPlaceholder() }
                    }
                    if (state.dates.data.orEmpty().isNotEmpty()) {
                        item(key = "dates") {
                            BroadcastDates(state.dates.data.orEmpty(), state.date, onDate, { showDates = true })
                        }
                    }
                }
                if (errors.isNotEmpty()) {
                    item(key = "refresh-error") {
                        Column(Modifier.padding(horizontal = 16.dp)) {
                            CachedErrorBanner(
                                errors.first().copy(message = errors.joinToString("\n") { it.message }),
                                state.contents.data.orEmpty().isNotEmpty(),
                                onRefresh
                            )
                        }
                    }
                }
                when {
                    loadingDates || loadingContents -> item(key = "loading-contents") {
                        Box(
                            Modifier.semantics {
                                contentDescription = "正在加载节目"
                                liveRegion = LiveRegionMode.Polite
                            }
                        ) { ArchiveContentPlaceholder() }
                    }
                    state.dates.data?.isEmpty() == true -> item(key = "empty-dates") {
                        StatePanel(
                            "暂无播出日期",
                            "该栏目暂时没有可回看的节目",
                            onRetry = if (errors.isEmpty()) onRefresh else null
                        )
                    }
                    state.contents.data?.isEmpty() == true -> item(key = "empty-contents") {
                        StatePanel(
                            "这一天暂无节目",
                            "可以选择其他播出日期",
                            onRetry = if (errors.isEmpty()) onRefresh else null
                        )
                    }
                    else -> {
                        if (state.contents.data.orEmpty().isNotEmpty()) {
                            item(key = "contents-heading") {
                                FlowRow(
                                    Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                    verticalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    Column(if (largeText) Modifier.fillMaxWidth() else Modifier.weight(1f)) {
                                        Text(
                                            state.date?.date?.format(BroadcastDateLabel) ?: "节目内容",
                                            style = MaterialTheme.typography.titleLarge
                                        )
                                        Text(
                                            "${state.fullEpisodes.size} 个完整节目 · ${state.clips.size} 个片段",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                    if (!state.selectionMode) {
                                        TextButton(onClick = onBeginSelection) { Text("批量下载") }
                                    }
                                }
                            }
                        }
                        items(state.fullEpisodes, key = { "full-${it.id}" }) { content ->
                            Column(Modifier.padding(horizontal = 16.dp)) {
                                EpisodeCard(
                                    content,
                                    true,
                                    state.selectionMode,
                                    content.id in state.selectedIds,
                                    {
                                        onPlay(content)
                                    },
                                    { onToggle(content.id) }
                                )
                            }
                        }
                        if (state.clips.isNotEmpty()) {
                            item(key = "clips-heading") {
                                Row(
                                    Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        "节目片段 · ${state.clips.size}",
                                        Modifier.weight(1f),
                                        style = MaterialTheme.typography.titleMedium
                                    )
                                    IconButton(
                                        onClick = onToggleClipSort,
                                        enabled = !state.selectionMode,
                                        modifier = Modifier.semantics {
                                            contentDescription = if (state.clipSortAscending) {
                                                "切换为时间降序"
                                            } else {
                                                "切换为时间升序"
                                            }
                                            stateDescription = if (state.clipSortAscending) "时间升序" else "时间降序"
                                        }
                                    ) {
                                        Icon(
                                            Icons.AutoMirrored.Outlined.Sort,
                                            null,
                                            Modifier.scale(
                                                scaleX = 1f,
                                                scaleY = if (state.clipSortAscending) -1f else 1f
                                            )
                                        )
                                    }
                                }
                            }
                        }
                        items(state.clips, key = { "clip-${it.id}" }) { content ->
                            Column(Modifier.padding(horizontal = 16.dp)) {
                                EpisodeCard(
                                    content,
                                    false,
                                    state.selectionMode,
                                    content.id in state.selectedIds,
                                    {
                                        onPlay(content)
                                    },
                                    { onToggle(content.id) },
                                    broadcastDate = state.date?.date
                                )
                            }
                        }
                    }
                }
            }
        }
        if (state.selectionMode) {
            Surface(shadowElevation = 4.dp) {
                Button(
                    onClick = { downloadIds = ArrayList(state.selectedIds) },
                    enabled = state.selectedIds.isNotEmpty(),
                    modifier = Modifier.fillMaxWidth().padding(16.dp).heightIn(min = TouchTarget)
                ) { Text("下载所选（${state.selectedIds.size}）") }
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
        DownloadQualitySheet(variants, selected.size, { quality ->
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
