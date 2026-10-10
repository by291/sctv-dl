package dev.sctvdl.data.settings

import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode

internal fun decodeSettings(values: Map<String, String?>): AppSettings = AppSettings(
    theme = ThemeMode.entries.firstOrNull { it.name == values["theme"] } ?: ThemeMode.System,
    dynamicColour = values["dynamic"]?.toBooleanStrictOrNull() ?: false,
    initialQuality =
    Quality.entries.firstOrNull { it.name == values["quality"] } ?: Quality.Standard,
    wifiOnlyDownloads = values["wifi"]?.toBooleanStrictOrNull() ?: false
)
