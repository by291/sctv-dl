package dev.sctvdl.design.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Update
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics

@Composable
fun ContentUpdateAction(onUpdate: () -> Unit, modifier: Modifier = Modifier) {
    IconButton(
        onClick = onUpdate,
        modifier = modifier.semantics {
            liveRegion = LiveRegionMode.Polite
            contentDescription = "有新内容，点击更新"
        }
    ) {
        BadgedBox(badge = { Badge(containerColor = MaterialTheme.colorScheme.primary) }) {
            Icon(Icons.Outlined.Update, null, tint = MaterialTheme.colorScheme.primary)
        }
    }
}
