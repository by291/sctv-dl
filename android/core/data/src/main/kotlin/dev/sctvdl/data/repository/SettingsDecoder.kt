package dev.sctvdl.data.repository

import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.ThemeMode

fun decodeSettings(values: Map<String, String?>): AppSettings = AppSettings(
    theme = ThemeMode.entries.firstOrNull { it.name == values["theme"] } ?: ThemeMode.System,
    dynamicColour = values["dynamic"]?.toBooleanStrictOrNull() ?: false,
    initialQuality =
    Quality.entries.firstOrNull { it.name == values["quality"] } ?: Quality.Standard,
    wifiOnlyDownloads = values["wifi"]?.toBooleanStrictOrNull() ?: false
)
