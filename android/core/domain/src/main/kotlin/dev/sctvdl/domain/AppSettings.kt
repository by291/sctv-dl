package dev.sctvdl.domain

enum class ThemeMode { System, Light, Dark }
data class AppSettings(
    val theme: ThemeMode = ThemeMode.System,
    val dynamicColour: Boolean = false,
    val initialQuality: Quality = Quality.Standard,
    val wifiOnlyDownloads: Boolean = false
)
