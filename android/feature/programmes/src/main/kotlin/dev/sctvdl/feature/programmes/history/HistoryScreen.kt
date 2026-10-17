package dev.sctvdl.feature.programmes.history

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.components.PrimaryTopAppBar
import dev.sctvdl.design.components.StatePanel
import dev.sctvdl.domain.history.ViewingKey
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.feature.programmes.history.components.HistoryCard
import java.time.ZoneId

@Composable
internal fun HistoryScreen(
    state: HistoryUiState,
    onBack: () -> Unit,
    onOpen: (ViewingTarget) -> Unit,
    onQuery: (String) -> Unit,
    onRemove: (ViewingKey) -> Unit,
    onRetry: () -> Unit
) {
    var searching by rememberSaveable { mutableStateOf(state.query.isNotEmpty()) }
    val list = rememberLazyListState()
    val closeSearch = {
        searching = false
        onQuery("")
    }
    val activeSearch = searching || state.query.isNotEmpty()
    BackHandler(activeSearch) { closeSearch() }

    Column(Modifier.fillMaxSize()) {
        PrimaryTopAppBar(
            title = { Text("观看记录") },
            navigationIcon = {
                IconButton(onClick = { if (activeSearch) closeSearch() else onBack() }) {
                    Icon(Icons.AutoMirrored.Outlined.ArrowBack, if (activeSearch) "退出搜索" else "返回节目库")
                }
            },
            actions = {
                IconButton(onClick = {
                    if (activeSearch) closeSearch() else searching = true
                }) { Icon(Icons.Outlined.Search, "搜索观看记录") }
            }
        )
        if (activeSearch) {
            OutlinedTextField(
                value = state.query,
                onValueChange = onQuery,
                label = { Text("搜索节目、栏目或日期") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
            )
        }
        if (state.error != null) StatePanel("观看记录暂不可用", state.error, false, onRetry)
        if (state.entries.isEmpty() && state.error == null) {
            StatePanel(
                if (state.loading) "加载观看记录" else "暂无观看记录",
                if (state.query.isBlank()) "播放过的节目会保存在这里" else "没有匹配的节目",
                state.loading
            )
        }
        LazyColumn(
            state = list,
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            state.entries.groupBy {
                it.viewedAt.atZone(ZoneId.systemDefault()).toLocalDate()
            }.forEach { (day, entries) ->
                item(key = "day:$day") { Text(day.toString(), Modifier.padding(vertical = 8.dp)) }
                items(entries, key = { it.key.toString() }) { entry ->
                    HistoryCard(entry, { onOpen(entry.target) }, { onRemove(entry.key) })
                }
            }
        }
    }
}
