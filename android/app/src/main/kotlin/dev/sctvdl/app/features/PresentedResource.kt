package dev.sctvdl.app.features

import dev.sctvdl.domain.CachedResource

// Keep the current browsing snapshot stable until the user accepts a newer cached result.
internal class PresentedResource<T> {
    var resource: CachedResource<T> = CachedResource()
        private set
    private var latest: CachedResource<T> = CachedResource()

    val hasUpdate: Boolean
        get() = resource.data != null && latest.data != null && resource.data != latest.data

    fun observe(value: CachedResource<T>): CachedResource<T> {
        latest = value
        resource = value.copy(
            data = resource.data ?: value.data,
            updatedAt = if (resource.data == null) value.updatedAt else resource.updatedAt
        )
        return resource
    }

    fun accept(): CachedResource<T> {
        resource = latest.copy(
            data = latest.data ?: resource.data,
            updatedAt = if (latest.data == null) resource.updatedAt else latest.updatedAt
        )
        return resource
    }
}
