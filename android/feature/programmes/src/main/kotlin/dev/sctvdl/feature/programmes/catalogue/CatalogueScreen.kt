package dev.sctvdl.feature.programmes.catalogue

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.Sort
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.components.ContentUpdateAction
import dev.sctvdl.design.components.SctvBrand
import dev.sctvdl.design.components.StatePanel
import dev.sctvdl.feature.programmes.catalogue.components.CatalogueSummaryPlaceholder
import dev.sctvdl.feature.programmes.catalogue.components.ProgrammeCard
import dev.sctvdl.feature.programmes.catalogue.components.ProgrammeCardPlaceholder
import dev.sctvdl.feature.programmes.catalogue.components.ProgrammeSpotlight
import dev.sctvdl.feature.programmes.catalogue.components.ProgrammeSpotlightPlaceholder
import dev.sctvdl.ui.feedback.CachedErrorBanner
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CatalogueScreen(
    state: CatalogueUiState,
    favouritesOnly: Boolean,
    onQuery: (String) -> Unit,
    onSort: (Boolean) -> Unit,
    onRefresh: () -> Unit,
    onFavourite: (String) -> Unit,
    onOpen: (String) -> Unit,
    onFilter: (Boolean) -> Unit,
    onExplore: () -> Unit = {},
    embedded: Boolean = false,
    onApplyUpdates: () -> Unit = {},
    catalogueScroll: LazyGridState = rememberLazyGridState(),
    favouritesScroll: LazyGridState = rememberLazyGridState()
) {
    val rows = state.rows(favouritesOnly)
    val initialLoading = state.resource.data == null && state.resource.error == null
    val showExploration = !embedded && !favouritesOnly && state.query.isBlank()
    val largeText = LocalDensity.current.fontScale >= 1.5f

    val scope = rememberCoroutineScope()
    var sortMenu by remember { mutableStateOf(false) }
    var searchExpanded by rememberSaveable { mutableStateOf(false) }
    var requestSearchFocus by remember { mutableStateOf(false) }
    // A programme can appear in both the spotlight and grid; only the clicked cover participates.
    var openedCover by rememberSaveable { mutableStateOf<String?>(null) }

    val searching = searchExpanded || state.query.isNotEmpty()
    val searchFocus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current

    val closeSearch: () -> Unit = {
        onQuery("")
        searchExpanded = false
        focusManager.clearFocus()
        keyboard?.hide()
    }

    BackHandler(searching) { closeSearch() }

    LaunchedEffect(requestSearchFocus) {
        if (requestSearchFocus) {
            searchFocus.requestFocus()
            requestSearchFocus = false
        }
    }

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = {
                if (searching) {
                    TextField(
                        value = state.query,
                        onValueChange = onQuery,
                        singleLine = true,
                        placeholder = { Text(if (favouritesOnly) "搜索收藏栏目" else "搜索栏目") },
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = {
                            focusManager.clearFocus()
                            keyboard?.hide()
                        }),
                        shape = MaterialTheme.shapes.medium,
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent
                        ),
                        modifier = Modifier.fillMaxWidth().focusRequester(searchFocus)
                    )
                } else if (embedded) {
                    Text("节目库")
                } else {
                    SctvBrand()
                }
            },
            expandedHeight = when {
                searching && largeText -> 88.dp
                searching || embedded -> 64.dp
                largeText -> 104.dp
                else -> 80.dp
            },
            navigationIcon = {
                if (searching) {
                    IconButton(onClick = closeSearch) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "退出搜索") }
                }
            },
            actions = {
                if (state.hasUpdate) {
                    ContentUpdateAction(onUpdate = {
                        onApplyUpdates()
                        scope.launch { (if (favouritesOnly) favouritesScroll else catalogueScroll).scrollToItem(0) }
                    })
                }
                if (!searching) {
                    IconButton(onClick = {
                        searchExpanded = true
                        requestSearchFocus = true
                    }) { Icon(Icons.Outlined.Search, "搜索栏目") }
                } else if (state.query.isNotEmpty()) {
                    IconButton(onClick = { onQuery("") }) { Icon(Icons.Outlined.Close, "清除搜索") }
                }
            }
        )
        PrimaryTabRow(selectedTabIndex = if (favouritesOnly) 1 else 0) {
            Tab(
                selected = !favouritesOnly,
                unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                onClick = { onFilter(false) },
                text = { Text("全部栏目") },
                modifier = Modifier.testTag("filter-all")
            )
            Tab(
                selected = favouritesOnly,
                unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                onClick = { onFilter(true) },
                text = { Text("我的收藏") },
                modifier = Modifier.testTag("filter-favourites")
            )
        }
        Column(Modifier.weight(1f).fillMaxWidth()) {
            LazyVerticalGrid(
                modifier = Modifier.weight(1f).fillMaxWidth().testTag("catalogue-grid"),
                state = if (favouritesOnly) favouritesScroll else catalogueScroll,
                columns = GridCells.Adaptive(if (largeText) 280.dp else 156.dp),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Keep the first key stable as cached data and the featured ID arrive independently.
                item(key = "library-header", span = { GridItemSpan(maxLineSpan) }) {
                    Column(
                        modifier = if (initialLoading) {
                            Modifier.semantics {
                                contentDescription = "正在加载栏目"
                                liveRegion = LiveRegionMode.Polite
                            }
                        } else {
                            Modifier
                        },
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        if (showExploration) {
                            if (initialLoading) {
                                ProgrammeSpotlightPlaceholder()
                            } else {
                                state.featured?.let { programme ->
                                    ProgrammeSpotlight(
                                        programme,
                                        state.resource.data.orEmpty().size > 1,
                                        {
                                            openedCover = "spotlight:${programme.id}"
                                            onOpen(programme.id)
                                        },
                                        onExplore,
                                        shareCover = !embedded && openedCover == "spotlight:${programme.id}"
                                    )
                                }
                            }
                        }
                        if (initialLoading) {
                            CatalogueSummaryPlaceholder()
                        } else {
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    if (state.resource.data != null) "${rows.size} 个栏目" else "正在获取栏目",
                                    Modifier.weight(1f),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Box {
                                    TextButton(onClick = { sortMenu = true }) {
                                        Icon(Icons.AutoMirrored.Outlined.Sort, null, Modifier.size(18.dp))
                                        Text(if (state.byName) "按名称" else "默认排序", Modifier.padding(start = 6.dp))
                                    }
                                    DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                                        DropdownMenuItem(text = { Text("默认排序") }, onClick = {
                                            onSort(false)
                                            sortMenu = false
                                        })
                                        DropdownMenuItem(text = { Text("按名称排序") }, onClick = {
                                            onSort(true)
                                            sortMenu = false
                                        })
                                    }
                                }
                            }
                        }
                    }
                }
                state.resource.error?.let { error ->
                    item(key = "error", span = { GridItemSpan(maxLineSpan) }) {
                        CachedErrorBanner(error, state.resource.data != null, onRefresh)
                    }
                }
                when {
                    initialLoading -> {
                        items(6, key = { "placeholder-$it" }) { ProgrammeCardPlaceholder(it) }
                    }
                    rows.isEmpty() && state.resource.data != null -> {
                        item(key = "empty", span = { GridItemSpan(maxLineSpan) }) {
                            StatePanel(
                                state.emptyReason(favouritesOnly),
                                when {
                                    state.query.isNotBlank() -> "试试其他关键词"
                                    favouritesOnly -> "点击栏目封面上的爱心即可收藏"
                                    else -> "稍后刷新查看最新节目"
                                },
                                onRetry = when {
                                    favouritesOnly && state.query.isBlank() -> {
                                        { onFilter(false) }
                                    }
                                    state.query.isBlank() && state.resource.error == null -> onRefresh
                                    else -> null
                                },
                                retryLabel = if (favouritesOnly) "浏览全部栏目" else "重试"
                            )
                        }
                    }
                    else -> items(rows, key = { it.id }) { row ->
                        ProgrammeCard(
                            row,
                            row.id in state.favourites,
                            {
                                openedCover = "card:${row.id}"
                                onOpen(row.id)
                            },
                            { onFavourite(row.id) },
                            shareCover = !embedded && openedCover == "card:${row.id}"
                        )
                    }
                }
            }
        }
    }
}
