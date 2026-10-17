package dev.sctvdl.data.downloads.managed

import dev.sctvdl.data.downloads.preflight.MediaIdentity
import java.io.IOException

internal class RestartRequiredException : IOException("The media resource cannot be safely resumed")

internal object ResumeValidator {
    fun validate(
        identity: MediaIdentity,
        position: Long,
        status: Int,
        contentRange: String?,
        etag: String?,
        lastModified: String?
    ) {
        if (position == 0L) {
            if (identity.etag != null && etag != identity.etag) throw RestartRequiredException()
            return
        }
        val sameResource = when {
            identity.etag != null -> identity.etag == etag
            identity.lastModified != null -> identity.lastModified == lastModified
            else -> false
        }
        val range = contentRange?.let { Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(it.trim()) }
        val start = range?.groupValues?.get(1)?.toLongOrNull()
        val end = range?.groupValues?.get(2)?.toLongOrNull()
        val total = range?.groupValues?.get(3)?.toLongOrNull()
        if (!identity.acceptsRanges || !sameResource || status != 206 || start != position || end == null ||
            end < position || total == null || end >= total ||
            (identity.totalBytes != null && identity.totalBytes != total)
        ) {
            throw RestartRequiredException()
        }
    }
}
