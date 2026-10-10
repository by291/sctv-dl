package dev.sctvdl.player.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties

@Composable
internal fun PlayerChoiceMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    maxHeight: Dp,
    content: @Composable ColumnScope.() -> Unit
) {
    val visibility = remember { MutableTransitionState(false) }
    visibility.targetState = expanded
    if (!visibility.currentState && !visibility.targetState) return

    val density = LocalDensity.current
    val gapPx = with(density) { 4.dp.roundToPx() }
    val position = remember(gapPx) { AboveControlPosition(gapPx) }
    val width = if (density.fontScale >= 1.5f) 112.dp else 72.dp
    val visibleRows = (maxHeight / 48.dp).toInt().coerceAtLeast(1)
    val height = (48.dp * visibleRows).coerceAtMost(maxHeight)

    Popup(
        popupPositionProvider = position,
        onDismissRequest = onDismiss,
        properties = PopupProperties(focusable = true)
    ) {
        AnimatedVisibility(
            visibleState = visibility,
            enter = fadeIn(tween(150)) + scaleIn(
                tween(150),
                initialScale = 0.95f,
                transformOrigin = TransformOrigin(0.5f, 1f)
            ),
            exit = fadeOut(tween(100))
        ) {
            Surface(
                shape = RoundedCornerShape(4.dp),
                color = MaterialTheme.colorScheme.scrim.copy(alpha = 0.6f),
                contentColor = Color.White
            ) {
                Column(
                    Modifier.width(width).heightIn(max = height).verticalScroll(rememberScrollState()),
                    content = content
                )
            }
        }
    }
}

@Composable
internal fun PlayerChoiceMenuItem(label: String, selected: Boolean, onClick: () -> Unit) {
    val bringIntoView = remember { BringIntoViewRequester() }

    LaunchedEffect(selected) {
        if (selected) bringIntoView.bringIntoView()
    }

    DropdownMenuItem(
        text = {
            Text(
                label,
                modifier = Modifier.fillMaxWidth(),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                textAlign = TextAlign.Center,
                maxLines = 1
            )
        },
        onClick = onClick,
        modifier = Modifier.heightIn(min = 48.dp).bringIntoViewRequester(bringIntoView)
            .semantics { this.selected = selected },
        colors = MenuDefaults.itemColors(textColor = if (selected) MaterialTheme.colorScheme.primary else Color.White),
        contentPadding = PaddingValues(horizontal = 8.dp)
    )
}

private class AboveControlPosition(private val gap: Int) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize
    ): IntOffset {
        val x = anchorBounds.left + (anchorBounds.width - popupContentSize.width) / 2
        val y = anchorBounds.top - popupContentSize.height - gap

        return IntOffset(
            x.coerceIn(0, (windowSize.width - popupContentSize.width).coerceAtLeast(0)),
            y.coerceIn(0, (windowSize.height - popupContentSize.height).coerceAtLeast(0))
        )
    }
}
