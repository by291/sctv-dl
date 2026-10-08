package dev.sctvdl.design

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.ThemeMode

private val Light = lightColorScheme(
    primary = Color(0xFFAD3D28), onPrimary = Color.White,
    primaryContainer = Color(0xFFFFDBD1), onPrimaryContainer = Color(0xFF3D0800),
    secondary = Color(0xFF667080), secondaryContainer = Color(0xFFEFF1F4),
    background = Color(0xFFF6F7F9), onBackground = Color(0xFF242A33),
    surface = Color(0xFFF6F7F9), onSurface = Color(0xFF242A33),
    surfaceContainer = Color(0xFFF0F2F5), surfaceContainerLow = Color.White,
    surfaceContainerHigh = Color(0xFFE8EBEF), surfaceVariant = Color(0xFFEFF1F4),
    onSurfaceVariant = Color(
        0xFF667080
    ),
    outline = Color(0xFF858C99), outlineVariant = Color(0xFFE1E5EB)
)
private val Dark = darkColorScheme(
    primary = Color(0xFFFFB4A4), onPrimary = Color(0xFF631500),
    primaryContainer = Color(0xFF8A2713), onPrimaryContainer = Color(0xFFFFDBD1),
    secondary = Color(0xFFA9AEB8), secondaryContainer = Color(0xFF343A45),
    background = Color(0xFF16191E), onBackground = Color(0xFFE7E9EE),
    surface = Color(0xFF16191E), onSurface = Color(0xFFE7E9EE),
    surfaceContainer = Color(0xFF262B33), surfaceContainerLow = Color(0xFF1E2229),
    surfaceContainerHigh = Color(0xFF2B3039), surfaceVariant = Color(0xFF343A45),
    onSurfaceVariant = Color(
        0xFFA9AEB8
    ),
    outline = Color(0xFF858C99), outlineVariant = Color(0xFF343A45)
)

@Composable
fun SctvTheme(settings: AppSettings, content: @Composable () -> Unit) {
    val dark = when (settings.theme) {
        ThemeMode.System -> isSystemInDarkTheme()
        ThemeMode.Light -> false
        ThemeMode.Dark -> true
    }
    val context = LocalContext.current
    val colours = if (settings.dynamicColour && Build.VERSION.SDK_INT >= 31) {
        if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    } else if (dark) {
        Dark
    } else {
        Light
    }
    MaterialTheme(colorScheme = colours, shapes = SctvShapes, content = content)
}
