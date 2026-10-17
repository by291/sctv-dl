package dev.sctvdl.domain.repository

import dev.sctvdl.domain.common.AppError

data class CacheCleanupResult(
    val metadataCleared: Boolean,
    val imagesCleared: Boolean,
    val metadataFailure: AppError? = null,
    val imageFailure: AppError? = null
)

interface StorageMaintenance {
    suspend fun clearCache(): CacheCleanupResult
}
