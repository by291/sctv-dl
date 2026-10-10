package dev.sctvdl.app.features.archive

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.BroadcastDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale

private val DateLabel = DateTimeFormatter.ofPattern("M月d日", Locale.SIMPLIFIED_CHINESE)
private val WeekdayLabel = DateTimeFormatter.ofPattern("EEEE", Locale.SIMPLIFIED_CHINESE)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BroadcastDateSheet(
    dates: List<BroadcastDate>,
    selectedId: String?,
    onSelect: (BroadcastDate) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = MaterialTheme.colorScheme.surface
    ) {
        Text(
            "选择播出日期",
            Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
            style = MaterialTheme.typography.headlineSmall
        )
        Text(
            "仅显示已有节目的日期",
            Modifier.padding(horizontal = 20.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyMedium
        )
        LazyColumn(
            Modifier.heightIn(max = 480.dp).selectableGroup(),
            contentPadding = PaddingValues(top = 24.dp, bottom = 24.dp)
        ) {
            dates.groupBy { YearMonth.from(it.date) }.forEach { (month, rows) ->
                item(key = "month-$month") {
                    Row(
                        Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("${month.year}年${month.monthValue}月", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "${rows.size} 个播出日",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.labelMedium
                        )
                    }
                }
                itemsIndexed(rows, key = { _, date -> date.id }) { index, date ->
                    val first = index == 0
                    val last = index == rows.lastIndex
                    val selected = date.id == selectedId
                    val groupShape = RoundedCornerShape(
                        topStart = if (first) 20.dp else 0.dp,
                        topEnd = if (first) 20.dp else 0.dp,
                        bottomStart = if (last) 20.dp else 0.dp,
                        bottomEnd = if (last) 20.dp else 0.dp
                    )
                    Surface(
                        modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = if (last) 24.dp else 0.dp),
                        shape = groupShape,
                        color = MaterialTheme.colorScheme.surfaceContainerLow
                    ) {
                        val rowShape = RoundedCornerShape(14.dp)
                        Row(
                            Modifier.fillMaxWidth()
                                .padding(horizontal = 6.dp)
                                .padding(top = if (first) 6.dp else 0.dp, bottom = if (last) 6.dp else 0.dp)
                                .clip(rowShape)
                                .background(
                                    if (selected) {
                                        MaterialTheme.colorScheme.primaryContainer
                                    } else {
                                        MaterialTheme.colorScheme.surfaceContainerLow
                                    },
                                    rowShape
                                )
                                .selectable(selected, role = Role.RadioButton, onClick = {
                                    onSelect(date)
                                    onDismiss()
                                })
                                .heightIn(min = 56.dp).padding(horizontal = 12.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            val selectedColor = MaterialTheme.colorScheme.onPrimaryContainer
                            Text(
                                date.date.format(DateLabel),
                                Modifier.weight(1f),
                                color = if (selected) selectedColor else MaterialTheme.colorScheme.onSurface,
                                style = MaterialTheme.typography.titleSmall
                            )
                            Text(
                                date.date.format(WeekdayLabel),
                                color = if (selected) selectedColor else MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodyMedium
                            )
                            Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                                if (selected) {
                                    Surface(shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.primary) {
                                        Icon(
                                            Icons.Outlined.Check,
                                            null,
                                            Modifier.padding(4.dp).size(16.dp),
                                            tint = MaterialTheme.colorScheme.onPrimary
                                        )
                                    }
                                } else {
                                    RadioButton(false, onClick = null)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
