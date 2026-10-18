package dev.sctvdl.feature.programmes.presentation

import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.CachedResource

/**
 * Presents the first available data immediately, then keeps it stable until [accept] applies a newer snapshot.
 * Refresh status and errors remain live so a failed refresh does not hide feedback or replace accepted rows.
 */
internal class AcceptedResourceState<T> {
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

    fun fail(error: AppError) {
        // A read failure changes feedback, never the accepted or pending data snapshot.
        resource = resource.copy(isRefreshing = false, error = error)
        latest = latest.copy(isRefreshing = false, error = error)
    }
}
