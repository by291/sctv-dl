package dev.sctvdl.app.features.catalogue

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
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Sort
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.ErrorBanner
import dev.sctvdl.design.ProgrammeCard
import dev.sctvdl.design.StatePanel

@Composable
fun CatalogueScreen(
    state: CatalogueUiState,
    favouritesOnly: Boolean,
    onQuery: (String) -> Unit,
    onSort: (Boolean) -> Unit,
    onRefresh: () -> Unit,
    onFavourite: (String) -> Unit,
    onOpen: (String) -> Unit,
    onSettings: () -> Unit
) {
    val rows = state.rows(favouritesOnly)
    val largeText = LocalDensity.current.fontScale >= 1.5f
    var sortMenu by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    if (favouritesOnly) "我的收藏" else "蜀台回看",
                    style = MaterialTheme.typography.headlineMedium
                )
                Text(
                    if (favouritesOnly) "喜欢的栏目，一次找到" else "四川精彩，随时回看",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(onClick = onSettings) { Icon(Icons.Outlined.Settings, "设置") }
        }
        OutlinedTextField(
            value = state.query, onValueChange = onQuery, singleLine = true, placeholder = {
                Text("搜索栏目")
            }, leadingIcon = { Icon(Icons.Outlined.Search, null) },
            trailingIcon = {
                if (state.query.isNotEmpty()) {
                    IconButton(onClick = {
                        onQuery("")
                    }) { Icon(Icons.Outlined.Close, "清除搜索") }
                }
            },
            keyboardOptions = KeyboardOptions(
                imeAction = ImeAction.Search
            ),
            shape = MaterialTheme.shapes.large,
            modifier = Modifier.fillMaxWidth().padding(
                horizontal = 16.dp
            )
        )
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                if (state.resource.data != null) {
                    "${if (favouritesOnly) "收藏栏目" else "全部栏目"} · ${rows.size}"
                } else {
                    "正在获取栏目"
                },
                Modifier.weight(1f),
                style = MaterialTheme.typography.titleSmall
            )
            Box {
                IconButton(onClick = { sortMenu = true }) { Icon(Icons.Outlined.Sort, "栏目排序") }
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
            IconButton(onClick = onRefresh, enabled = !state.resource.isRefreshing) {
                Icon(Icons.Outlined.Refresh, "刷新栏目")
            }
        }
        if (state.resource.isRefreshing &&
            state.resource.data != null
        ) {
            LinearProgressIndicator(Modifier.fillMaxWidth())
        }
        state.resource.error?.let {
            Box(Modifier.padding(horizontal = 16.dp)) {
                ErrorBanner(
                    it,
                    state.resource.data != null,
                    onRefresh
                )
            }
        }
        when {
            state.resource.data == null && state.resource.error == null -> StatePanel(
                "加载栏目",
                "正在连接节目服务",
                loading = true
            )
            rows.isEmpty() && state.resource.data != null -> StatePanel(
                state.emptyReason(favouritesOnly),
                if (state.query.isNotBlank()) {
                    "试试其他关键词"
                } else if (favouritesOnly) {
                    "点击栏目封面上的爱心即可收藏"
                } else {
                    "稍后刷新查看最新节目"
                },
                onRetry = if (!favouritesOnly &&
                    state.query.isBlank()
                ) {
                    onRefresh
                } else {
                    null
                }
            )
            else -> LazyVerticalGrid(
                modifier = Modifier.testTag("catalogue-grid"),
                columns = GridCells.Adaptive(if (largeText) 280.dp else 156.dp),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(rows, key = {
                    it.id
                }) { row ->
                    ProgrammeCard(row, row.id in state.favourites, {
                        onOpen(row.id)
                    }, { onFavourite(row.id) })
                }
            }
        }
    }
}
