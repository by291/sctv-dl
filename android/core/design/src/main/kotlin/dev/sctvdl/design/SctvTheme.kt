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
    secondary = Color(0xFF675C55), secondaryContainer = Color(0xFFF0E5DE),
    background = Color(0xFFFBF8F5), onBackground = Color(0xFF241D19),
    surface = Color(0xFFFBF8F5), onSurface = Color(0xFF241D19),
    surfaceContainer = Color(0xFFF4ECE6), surfaceContainerLow = Color.White,
    surfaceContainerHigh = Color(0xFFEFE5DE), surfaceVariant = Color(0xFFF0E5DE),
    onSurfaceVariant = Color(
        0xFF675C55
    ),
    outline = Color(0xFF87766C), outlineVariant = Color(0xFFE4D8CE)
)
private val Dark = darkColorScheme(
    primary = Color(0xFFFFB4A4), onPrimary = Color(0xFF631500),
    primaryContainer = Color(0xFF8A2713), onPrimaryContainer = Color(0xFFFFDBD1),
    secondary = Color(0xFFD0BFB5), secondaryContainer = Color(0xFF51443B),
    background = Color(0xFF171311), onBackground = Color(0xFFF0DFD6),
    surface = Color(0xFF171311), onSurface = Color(0xFFF0DFD6),
    surfaceContainer = Color(0xFF2B231E), surfaceContainerLow = Color(0xFF231D19),
    surfaceContainerHigh = Color(0xFF352B24), surfaceVariant = Color(0xFF51443B),
    onSurfaceVariant = Color(
        0xFFD0BFB5
    ),
    outline = Color(0xFF9E8D82), outlineVariant = Color(0xFF51443B)
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
