package dev.sctvdl.data.downloads.preflight

import dev.sctvdl.data.network.UpstreamUrlPolicy
import dev.sctvdl.domain.download.isActive
import java.io.IOException
import javax.inject.Inject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response

internal class OkHttpMediaProbe @Inject constructor(private val client: OkHttpClient) : MediaProbe {
    override suspend fun request(url: String, method: String, range: String?): ProbeResponse =
        suspendCancellableCoroutine { continuation ->
            val request = Request.Builder()
                .url(url)
                .method(method, null)
                .header("Referer", UpstreamUrlPolicy.REFERER)
                .apply { range?.let { header("Range", it) } }
                .build()
            val call = client.newCall(request)

            continuation.invokeOnCancellation { call.cancel() }

            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    val result = response.use {
                        val total = it.header("Content-Range")?.let { header ->
                            Regex("bytes \\d+-\\d+/(\\d+)")
                                .matchEntire(header.trim())?.groupValues?.get(1)?.toLongOrNull()
                        }

                        ProbeResponse(
                            it.code,
                            it.header("Content-Type"),
                            it.header("Content-Length")?.toLongOrNull(),
                            total
                        )
                    }

                    if (continuation.isActive) continuation.resume(result)
                }
            })
        }
}
