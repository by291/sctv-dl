package dev.sctvdl.app.platform

import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.repository.CacheCleanupResult
import dev.sctvdl.domain.repository.StorageMaintenance
import kotlinx.coroutines.CancellationException

internal class AppStorageMaintenance(
    private val clearMetadata: suspend () -> Unit,
    private val clearImages: suspend () -> Unit
) : StorageMaintenance {
    override suspend fun clearCache(): CacheCleanupResult {
        val metadataFailure = clear("节目信息缓存清理失败", clearMetadata)
        val imageFailure = clear("图片缓存清理失败", clearImages)
        return CacheCleanupResult(metadataFailure == null, imageFailure == null, metadataFailure, imageFailure)
    }

    private suspend fun clear(message: String, action: suspend () -> Unit): AppError? = try {
        action()
        null
    } catch (failure: CancellationException) {
        throw failure
    } catch (_: Exception) {
        AppError(ErrorKind.Storage, message)
    }
}
