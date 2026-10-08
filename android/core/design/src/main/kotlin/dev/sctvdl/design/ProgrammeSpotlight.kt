package dev.sctvdl.design

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.Shuffle
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.Programme

@Composable
fun ProgrammeSpotlight(programme: Programme, canChange: Boolean, onOpen: () -> Unit, onChange: () -> Unit) {
    val colours = MaterialTheme.colorScheme
    val largeText = LocalDensity.current.fontScale >= 1.5f
    Surface(
        color = colours.primaryContainer.copy(alpha = 0.35f),
        shape = MaterialTheme.shapes.large,
        modifier = Modifier.fillMaxWidth().testTag("programme-spotlight")
    ) {
        BoxWithConstraints(Modifier.padding(16.dp)) {
            val wide = maxWidth >= 480.dp && !largeText
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("栏目探索", style = MaterialTheme.typography.labelLarge, color = colours.primary)
                        Text(
                            programme.name,
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = if (largeText) 4 else 2,
                            overflow = TextOverflow.Ellipsis
                        )
                        if (wide) {
                            Text(
                                "发现一个栏目，回看整期节目或精彩片段。",
                                style = MaterialTheme.typography.bodyMedium,
                                color = colours.onSurfaceVariant
                            )
                        }
                    }
                    if (!largeText) {
                        CoverImage(
                            programme.coverUrl,
                            Modifier.width(if (wide) 160.dp else 88.dp).aspectRatio(16f / 9f)
                                .clip(MaterialTheme.shapes.small)
                        )
                    }
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilledTonalButton(
                        onClick = onOpen,
                        contentPadding = PaddingValues(horizontal = 14.dp),
                        modifier = Modifier.heightIn(min = TouchTarget).semantics {
                            contentDescription = "查看栏目${programme.name}"
                        }
                    ) {
                        Text("查看节目")
                        Icon(Icons.AutoMirrored.Outlined.ArrowForward, null, Modifier.padding(start = 6.dp).size(18.dp))
                    }
                    TextButton(
                        onClick = onChange,
                        enabled = canChange,
                        modifier = Modifier.heightIn(min = TouchTarget).semantics { contentDescription = "换一个栏目" }
                    ) {
                        Icon(Icons.Outlined.Shuffle, null, Modifier.size(18.dp))
                        Text("换一个", Modifier.padding(start = 6.dp))
                    }
                }
            }
        }
    }
}
