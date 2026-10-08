package dev.sctvdl.design

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.pullToRefresh
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics

@Composable
fun RefreshableContent(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable BoxScope.() -> Unit
) {
    val pullState = rememberPullToRefreshState()
    val canRefresh = enabled && !isRefreshing

    Box(
        modifier.pullToRefresh(isRefreshing, pullState, enabled = canRefresh, onRefresh = {
            if (canRefresh) onRefresh()
        }).semantics {
            customActions = if (canRefresh) {
                listOf(
                    CustomAccessibilityAction("刷新") {
                        onRefresh()
                        true
                    }
                )
            } else {
                emptyList()
            }
        }
    ) {
        content()
        PullToRefreshDefaults.Indicator(pullState, isRefreshing, Modifier.align(Alignment.TopCenter))
    }
}
