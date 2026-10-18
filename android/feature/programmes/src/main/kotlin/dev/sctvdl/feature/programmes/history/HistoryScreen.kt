package dev.sctvdl.feature.programmes.history

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.SearchOff
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Snackbar
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.components.PrimaryTopAppBar
import dev.sctvdl.design.components.StatePanel
import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingKey
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.feature.programmes.history.components.HistoryCard
import java.time.LocalDate
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
    var requestSearchFocus by remember { mutableStateOf(false) }
    val list = rememberLazyListState()
    val focus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    val closeSearch: () -> Unit = {
        searching = false
        onQuery("")
        focusManager.clearFocus()
        keyboard?.hide()
    }
    val activeSearch = searching || state.query.isNotEmpty()
    val groups = groupHistory(state.entries)

    BackHandler(activeSearch) { closeSearch() }
    LaunchedEffect(requestSearchFocus) {
        if (requestSearchFocus) {
            focus.requestFocus()
            requestSearchFocus = false
        }
    }

    Column(Modifier.fillMaxSize()) {
        PrimaryTopAppBar(
            title = {
                if (activeSearch) {
                    TextField(
                        value = state.query,
                        onValueChange = onQuery,
                        singleLine = true,
                        placeholder = { Text("搜索观看记录") },
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = {
                            focusManager.clearFocus()
                            keyboard?.hide()
                        }),
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = Color.Transparent,
                            unfocusedContainerColor = Color.Transparent,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent
                        ),
                        modifier = Modifier.fillMaxWidth().focusRequester(focus)
                    )
                } else {
                    Text("观看历史")
                }
            },
            navigationIcon = {
                IconButton(onClick = { if (activeSearch) closeSearch() else onBack() }) {
                    Icon(Icons.AutoMirrored.Outlined.ArrowBack, if (activeSearch) "退出搜索" else "返回节目库")
                }
            },
            actions = {
                IconButton(onClick = {
                    if (activeSearch) {
                        closeSearch()
                    } else {
                        searching = true
                        requestSearchFocus = true
                    }
                }) {
                    Icon(
                        if (activeSearch) Icons.Outlined.Close else Icons.Outlined.Search,
                        if (activeSearch) "关闭搜索" else "搜索观看记录"
                    )
                }
            }
        )
        Box(Modifier.weight(1f)) {
            LazyColumn(
                state = list,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (state.entries.isEmpty()) {
                    item(key = "history-state") {
                        Column(Modifier.fillParentMaxHeight(), verticalArrangement = Arrangement.Center) {
                            when {
                                state.error != null -> StatePanel(
                                    "观看记录读取失败",
                                    state.error,
                                    onRetry = onRetry,
                                    icon = Icons.Outlined.History
                                )
                                state.loading -> StatePanel("加载观看记录", "", loading = true)
                                state.query.isNotBlank() -> StatePanel(
                                    "没有匹配的观看记录",
                                    "试试节目名称，或清除搜索查看全部记录。",
                                    onRetry = closeSearch,
                                    retryLabel = "清除搜索",
                                    icon = Icons.Outlined.SearchOff
                                )
                                else -> StatePanel(
                                    "暂无观看记录",
                                    "观看节目后，可以在这里继续播放。",
                                    icon = Icons.Outlined.History
                                )
                            }
                        }
                    }
                }
                groups.forEachIndexed { groupIndex, (label, entries) ->
                    itemsIndexed(entries, key = { _, entry -> entry.key.toString() }) { index, entry ->
                        Column {
                            if (index == 0) {
                                val topSpacing = if (groupIndex == 0) 0.dp else 8.dp
                                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                                    Text(
                                        label,
                                        Modifier.widthIn(max = 720.dp).fillMaxWidth()
                                            .padding(
                                                start = 4.dp,
                                                top = topSpacing,
                                                bottom = 8.dp
                                            )
                                            .semantics { heading() },
                                        style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                            HistoryCard(entry, { onOpen(entry.target) }, { onRemove(entry.key) })
                        }
                    }
                }
            }
            if (state.entries.isNotEmpty()) {
                state.error?.let { message ->
                    // Preserve the list viewport and keep retry available if observing history has stopped.
                    Snackbar(
                        action = { TextButton(onClick = onRetry) { Text("重试") } },
                        modifier = Modifier.align(Alignment.BottomCenter).padding(16.dp)
                    ) { Text(message) }
                }
            }
        }
    }
}

private fun groupHistory(entries: List<ViewingEntry>): List<Pair<String, List<ViewingEntry>>> {
    val today = LocalDate.now()
    val zone = ZoneId.systemDefault()
    // Compare calendar days, not elapsed 24-hour windows, across local daylight-saving boundaries.
    val yesterday = today.minusDays(1)
    val groups = entries.sortedWith(compareByDescending<ViewingEntry> { it.viewedAt }.thenBy { it.key.toString() })
        .groupBy {
            when (it.viewedAt.atZone(zone).toLocalDate()) {
                today -> "今天"
                yesterday -> "昨天"
                else -> "更早"
            }
        }
    return listOf("今天", "昨天", "更早").mapNotNull { label -> groups[label]?.let { label to it } }
}
