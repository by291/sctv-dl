package dev.sctvdl.domain.settings

import dev.sctvdl.domain.media.Quality

enum class ThemeMode { System, Light, Dark }

data class AppSettings(
    val theme: ThemeMode = ThemeMode.System,
    val dynamicColour: Boolean = false,
    val initialQuality: Quality = Quality.Standard,
    val wifiOnlyDownloads: Boolean = false
)
