package dev.sctvdl.feature.programmes.catalogue

import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.sortProgrammes

internal data class CatalogueUiState(
    val resource: CachedResource<List<Programme>> = CachedResource(),
    val favourites: Set<String> = emptySet(),
    val orderingFavourites: Set<String> = favourites,
    val query: String = "",
    val byName: Boolean = false,
    val favouritesOnly: Boolean = false,
    val featuredId: String? = null,
    val hasUpdate: Boolean = false
) {
    val featured: Programme? get() = resource.data.orEmpty().find { it.id == featuredId }

    fun rows(favouritesOnly: Boolean): List<Programme> = sortProgrammes(
        resource.data.orEmpty(),
        if (favouritesOnly) favourites else orderingFavourites,
        byName
    )
        .filter {
            (!favouritesOnly || it.id in favourites) &&
                it.name.contains(query.trim(), ignoreCase = true)
        }

    fun emptyReason(favouritesOnly: Boolean): String = when {
        query.isNotBlank() -> "没有匹配的栏目"
        favouritesOnly -> "还没有收藏栏目"
        else -> "暂无栏目"
    }
}
