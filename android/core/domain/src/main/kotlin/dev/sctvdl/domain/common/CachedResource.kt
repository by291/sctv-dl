package dev.sctvdl.domain.common

import java.time.Instant

data class CachedResource<T>(
    val data: T? = null,
    val isRefreshing: Boolean = false,
    val error: AppError? = null,
    val updatedAt: Instant? = null
)
