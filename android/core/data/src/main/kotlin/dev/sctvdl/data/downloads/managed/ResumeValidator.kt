package dev.sctvdl.data.downloads.managed

import dev.sctvdl.data.downloads.preflight.MediaIdentity
import java.io.IOException

internal class RestartRequiredException : IOException("The media resource cannot be safely resumed")

internal data class MediaResponse(
    val status: Int,
    val contentRange: String? = null,
    val etag: String? = null,
    val lastModified: String? = null
)

internal object ResumeValidator {
    /** Reject responses that could append bytes from a different resource or offset. */
    fun validate(identity: MediaIdentity, position: Long, response: MediaResponse) {
        // A fresh transfer appends nothing, but a known ETag must still match preflight.
        if (position == 0L) {
            if (identity.etag != null && response.etag != identity.etag) {
                throw RestartRequiredException()
            }
            return
        }

        // Resume checks the same preferred validator used to build the If-Range request.
        val isSameResource = when {
            identity.etag != null -> identity.etag == response.etag
            identity.lastModified != null -> identity.lastModified == response.lastModified
            else -> false
        }
        val range = response.contentRange?.let { Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(it.trim()) }
        val start = range?.groupValues?.get(1)?.toLongOrNull()
        val end = range?.groupValues?.get(2)?.toLongOrNull()
        val total = range?.groupValues?.get(3)?.toLongOrNull()

        // A matching validator alone cannot prove that the returned bytes start where the cache ends.
        val isExactRange = start == position && end != null && total != null && end in position until total
        val isSameLength = identity.totalBytes == null || identity.totalBytes == total
        if (!identity.acceptsRanges || !isSameResource || response.status != 206 || !isExactRange || !isSameLength) {
            throw RestartRequiredException()
        }
    }
}
