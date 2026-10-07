package dev.sctvdl.app.features.archive

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.BroadcastDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale

private val DateLabel = DateTimeFormatter.ofPattern("M月d日 EEEE", Locale.SIMPLIFIED_CHINESE)

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
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Text(
            "选择播出日期",
            Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
            style = MaterialTheme.typography.headlineSmall
        )
        Text(
            "仅显示已有节目的日期",
            Modifier.padding(horizontal = 20.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        LazyColumn(
            Modifier.heightIn(max = 480.dp),
            contentPadding = PaddingValues(bottom = 24.dp)
        ) {
            dates.groupBy { YearMonth.from(it.date) }.forEach { (month, rows) ->
                item(key = "month-$month") {
                    Text(
                        "${month.year}年${month.monthValue}月",
                        Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
                items(rows, key = { it.id }) { date ->
                    ListItem(
                        headlineContent = {
                            Text(date.date.format(DateLabel))
                        },
                        trailingContent = {
                            RadioButton(
                                selected =
                                date.id == selectedId,
                                onClick = null
                            )
                        },
                        modifier = Modifier.clickable {
                            onSelect(date)
                            onDismiss()
                        }
                    )
                }
            }
        }
    }
}
