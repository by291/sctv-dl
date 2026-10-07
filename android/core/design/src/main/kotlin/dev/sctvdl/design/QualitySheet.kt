package dev.sctvdl.design

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.VideoVariant

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QualitySheet(variants: List<VideoVariant>, batchCount: Int, onSelect: (Quality) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("选择下载清晰度", Modifier.weight(1f), style = MaterialTheme.typography.headlineSmall)
                IconButton(onClick = onDismiss) { Icon(Icons.Outlined.Close, "关闭清晰度选择") }
            }
            Text(
                if (batchCount > 1) {
                    "共 $batchCount 个节目，缺少所选清晰度时使用可用版本"
                } else {
                    "保存到系统下载目录"
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            variants.distinctBy { it.quality }.forEach { variant ->
                FilledTonalButton(
                    onClick = {
                        onSelect(variant.quality)
                    },
                    modifier = Modifier.fillMaxWidth().heightIn(
                        min = 56.dp
                    ),
                    shape = MaterialTheme.shapes.medium
                ) {
                    Text(
                        variant.quality.label,
                        Modifier.weight(1f),
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        if (variant.quality == Quality.Standard) {
                            "画面更清晰"
                        } else {
                            "节省存储空间"
                        },
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        }
    }
}
