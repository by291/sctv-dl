package dev.sctvdl.design.theme

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.material3.ColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

@Composable
internal fun animatedColourScheme(target: ColorScheme): ColorScheme = target.copy(
    primary = animateColour(target.primary),
    onPrimary = animateColour(target.onPrimary),
    primaryContainer = animateColour(target.primaryContainer),
    onPrimaryContainer = animateColour(target.onPrimaryContainer),
    inversePrimary = animateColour(target.inversePrimary),
    secondary = animateColour(target.secondary),
    onSecondary = animateColour(target.onSecondary),
    secondaryContainer = animateColour(target.secondaryContainer),
    onSecondaryContainer = animateColour(target.onSecondaryContainer),
    tertiary = animateColour(target.tertiary),
    onTertiary = animateColour(target.onTertiary),
    tertiaryContainer = animateColour(target.tertiaryContainer),
    onTertiaryContainer = animateColour(target.onTertiaryContainer),
    background = animateColour(target.background),
    onBackground = animateColour(target.onBackground),
    surface = animateColour(target.surface),
    onSurface = animateColour(target.onSurface),
    surfaceVariant = animateColour(target.surfaceVariant),
    onSurfaceVariant = animateColour(target.onSurfaceVariant),
    surfaceTint = animateColour(target.surfaceTint),
    inverseSurface = animateColour(target.inverseSurface),
    inverseOnSurface = animateColour(target.inverseOnSurface),
    error = animateColour(target.error),
    onError = animateColour(target.onError),
    errorContainer = animateColour(target.errorContainer),
    onErrorContainer = animateColour(target.onErrorContainer),
    outline = animateColour(target.outline),
    outlineVariant = animateColour(target.outlineVariant),
    scrim = animateColour(target.scrim),
    surfaceBright = animateColour(target.surfaceBright),
    surfaceDim = animateColour(target.surfaceDim),
    surfaceContainer = animateColour(target.surfaceContainer),
    surfaceContainerHigh = animateColour(target.surfaceContainerHigh),
    surfaceContainerHighest = animateColour(target.surfaceContainerHighest),
    surfaceContainerLow = animateColour(target.surfaceContainerLow),
    surfaceContainerLowest = animateColour(target.surfaceContainerLowest),
    primaryFixed = animateColour(target.primaryFixed),
    primaryFixedDim = animateColour(target.primaryFixedDim),
    onPrimaryFixed = animateColour(target.onPrimaryFixed),
    onPrimaryFixedVariant = animateColour(target.onPrimaryFixedVariant),
    secondaryFixed = animateColour(target.secondaryFixed),
    secondaryFixedDim = animateColour(target.secondaryFixedDim),
    onSecondaryFixed = animateColour(target.onSecondaryFixed),
    onSecondaryFixedVariant = animateColour(target.onSecondaryFixedVariant),
    tertiaryFixed = animateColour(target.tertiaryFixed),
    tertiaryFixedDim = animateColour(target.tertiaryFixedDim),
    onTertiaryFixed = animateColour(target.onTertiaryFixed),
    onTertiaryFixedVariant = animateColour(target.onTertiaryFixedVariant)
)

// Native colour animation handles interruption and the system's animator duration scale.
@Composable
private fun animateColour(target: Color): Color = animateColorAsState(
    targetValue = target,
    animationSpec = tween(THEME_TRANSITION_DURATION_MILLIS),
    label = "Theme colour"
).value
