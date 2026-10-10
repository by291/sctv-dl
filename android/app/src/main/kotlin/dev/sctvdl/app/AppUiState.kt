package dev.sctvdl.app

import dev.sctvdl.domain.settings.AppSettings

internal data class AppUiState(val settings: AppSettings = AppSettings(), val downloadMessage: AppMessage? = null)
internal data class AppMessage(val id: Long, val text: String)
