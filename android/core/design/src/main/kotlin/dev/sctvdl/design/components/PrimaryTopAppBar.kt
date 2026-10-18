package dev.sctvdl.design.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrimaryTopAppBar(
    title: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    navigationIcon: @Composable () -> Unit = {},
    actions: @Composable RowScope.() -> Unit = {}
) {
    // Reserve the same space for large text and search without shifting primary page content.
    val height = if (LocalDensity.current.fontScale >= 1.5f) 88.dp else 64.dp

    TopAppBar(
        title = title,
        // The theme already animates this surface; the app bar's own colour animation would lag behind it.
        modifier = modifier.background(MaterialTheme.colorScheme.surface),
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = Color.Transparent,
            scrolledContainerColor = Color.Transparent
        ),
        expandedHeight = height,
        navigationIcon = navigationIcon,
        actions = actions
    )
}
