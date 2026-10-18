package dev.sctvdl.feature.downloads.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.download.supportedActions
import dev.sctvdl.feature.downloads.DownloadsUiState
import dev.sctvdl.feature.downloads.label

@Composable
internal fun DownloadSelectionBar(
    state: DownloadsUiState,
    enabled: Boolean,
    onAction: (DownloadAction, List<DownloadTarget>) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selected = state.visible.filter { it.id in state.selection }
    val targetsByAction = DownloadAction.entries.associateWith { action ->
        selected.filter { action in supportedActions(it) }.map { task ->
            DownloadTarget(task.id, state.selection.getValue(task.id))
        }
    }.filterValues { it.isNotEmpty() }

    FlowRow(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(Modifier.padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (state.busy) "正在处理…" else "仅操作所选任务",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (state.busy) {
                Spacer(Modifier.width(8.dp))
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            }
        }
        Box {
            TextButton(onClick = { expanded = true }, enabled = enabled && targetsByAction.isNotEmpty()) {
                Icon(Icons.Outlined.Tune, null, Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text("批量操作")
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                targetsByAction.forEach { (action, targets) ->
                    DropdownMenuItem(text = { Text("${action.label} · ${targets.size}") }, onClick = {
                        expanded = false
                        onAction(action, targets)
                    })
                }
            }
        }
    }
}
