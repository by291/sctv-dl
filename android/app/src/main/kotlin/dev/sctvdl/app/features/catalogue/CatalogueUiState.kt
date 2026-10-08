package dev.sctvdl.app.features.catalogue

import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.Programme
import dev.sctvdl.domain.sortProgrammes

data class CatalogueUiState(
    val resource: CachedResource<List<Programme>> = CachedResource(),
    val favourites: Set<String> = emptySet(),
    val query: String = "",
    val byName: Boolean = false,
    val favouritesOnly: Boolean = false,
    val featuredId: String? = null
) {
    val featured: Programme? get() = resource.data.orEmpty().find { it.id == featuredId }

    fun rows(favouritesOnly: Boolean): List<Programme> = sortProgrammes(
        resource.data.orEmpty(),
        favourites,
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
