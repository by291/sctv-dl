package dev.sctvdl.data.downloads.preflight

import dev.sctvdl.data.network.UpstreamUrlPolicy
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.AppException
import dev.sctvdl.domain.common.ErrorKind

internal data class ProbeResponse(
    val status: Int,
    val contentType: String?,
    val contentLength: Long? = null,
    val totalBytes: Long? = null,
    val etag: String? = null,
    val lastModified: String? = null,
    val acceptsRanges: Boolean = false
)

internal data class MediaIdentity(
    val totalBytes: Long?,
    val etag: String?,
    val lastModified: String?,
    val acceptsRanges: Boolean
)

internal fun interface MediaProbe {
    suspend fun request(url: String, method: String, range: String?): ProbeResponse
}

/** Validates media headers without downloading the episode; a missing total size remains unknown. */
internal class MediaPreflight(private val probe: MediaProbe) {
    suspend fun check(url: String): Long? = inspect(url).totalBytes

    suspend fun inspect(url: String): MediaIdentity {
        val target = UpstreamUrlPolicy.media(url) ?: throw AppException(AppError(ErrorKind.UnsafeUrl, "视频地址不受支持"))

        var response = probe.request(target, "HEAD", null)
        val range = response.status == 405 || response.status == 501
        // Some upstream hosts reject HEAD; probe one byte instead of buffering the MP4 response.
        if (range) response = probe.request(target, "GET", "bytes=0-0")

        if (response.status !in listOf(200, 206)) {
            throw AppException(
                AppError(ErrorKind.Http, "视频暂时无法下载（${response.status}）", response.status)
            )
        }

        val type = response.contentType?.substringBefore(';')?.trim()?.lowercase()
        if (type !in setOf("video/mp4", "application/octet-stream")) {
            throw AppException(AppError(ErrorKind.InvalidData, "上游未返回可下载的视频文件"))
        }

        // Content-Length on a partial response describes the probe, not the complete download.
        val total = (
            if (range && response.status == 206) {
                response.totalBytes
            } else {
                response.contentLength
            }
            )?.takeIf { it > 0 }
        return MediaIdentity(
            total,
            response.etag?.takeUnless { it.startsWith("W/", true) },
            response.lastModified,
            response.acceptsRanges || response.status == 206
        )
    }
}
