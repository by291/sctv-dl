package dev.sctvdl.app.navigation

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

@Serializable
sealed interface AppRoute : NavKey {
    @Serializable data object Catalogue : AppRoute

    @Serializable data object Favourites : AppRoute

    @Serializable data object Downloads : AppRoute

    @Serializable data object Settings : AppRoute

    @Serializable data class Archive(val programmeId: String) : AppRoute

    @Serializable
    data class Playback(val programmeId: String, val dateId: String, val contentId: String) : AppRoute

    @Serializable data class LocalPlayback(val taskId: String) : AppRoute
}
