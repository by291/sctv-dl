package dev.sctvdl.data.network

import okhttp3.HttpUrl.Companion.toHttpUrl

internal object UpstreamUrlPolicy {
    const val REFERER = "https://scgc.video.play/"
    private val mediaBase = "https://fscgc.scgchc.com/".toHttpUrl()
    private val coverBase = "https://kscgc.sctv.com/".toHttpUrl()
    private val coverHosts = setOf("kscgc.sctv.com", "kscgc.scgchc.com", "kscgc.sctv-tf.com")

    fun media(value: String?): String? {
        val url = value?.trim()?.takeIf(String::isNotEmpty)?.let(mediaBase::resolve) ?: return null
        if (!url.isHttps || url.host != mediaBase.host || url.port != 443 ||
            url.username.isNotEmpty() ||
            url.password.isNotEmpty()
        ) {
            return null
        }
        return url.takeIf { it.encodedPath.endsWith(".mp4", ignoreCase = true) }?.toString()
    }

    fun cover(value: String?): String? {
        val url = value?.trim()?.takeIf(String::isNotEmpty)?.let(coverBase::resolve) ?: return null
        return url.takeIf {
            it.isHttps && it.host in coverHosts && it.port == 443 &&
                it.username.isEmpty() &&
                it.password.isEmpty()
        }?.toString()
    }
}
