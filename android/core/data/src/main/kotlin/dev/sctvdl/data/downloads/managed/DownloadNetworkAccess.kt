package dev.sctvdl.data.downloads.managed

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.sctvdl.data.downloads.preflight.MediaIdentity
import dev.sctvdl.data.network.UpstreamUrlPolicy
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.network.UpstreamRequestProfile
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton
import okhttp3.ConnectionPool
import okhttp3.Dispatcher
import okhttp3.OkHttpClient

internal enum class ExecutionOwner { Foreground, UnrestrictedJob, WifiJob, LocalJob }

internal class ExecutionLease(private val release: () -> Unit) : AutoCloseable {
    private val closed = java.util.concurrent.atomic.AtomicBoolean()

    override fun close() {
        if (closed.compareAndSet(false, true)) release()
    }
}

/** Permission and sockets share an owner. A lost lease/network cancels calls before another network can be used. */
@Singleton
internal class DownloadNetworkAccess @Inject constructor(
    @ApplicationContext context: Context,
    private val baseClient: OkHttpClient
) {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val owners = ConcurrentHashMap<String, ExecutionOwner>()

    private data class Connection(
        val task: DownloadTask,
        val network: Network,
        val client: OkHttpClient,
        val calls: MutableSet<okhttp3.Call>
    ) {
        fun close() {
            // Dispatcher no longer owns a call once asynchronous headers have been delivered.
            calls.forEach { it.cancel() }
            client.dispatcher.cancelAll()
            client.connectionPool.evictAll()
            client.dispatcher.executorService.shutdown()
        }
    }

    private val clients = ConcurrentHashMap<String, Connection>()
    private val blocked = ConcurrentHashMap.newKeySet<String>()
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onLost(network: Network) {
            clients.filterValues { it.network == network }.keys.forEach(::cancel)
        }

        override fun onAvailable(network: Network) {
            cancelDisallowed()
        }

        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            cancelDisallowed()
        }
    }

    @Synchronized fun acquire(owner: ExecutionOwner): ExecutionLease {
        if (owners.isEmpty()) connectivity.registerDefaultNetworkCallback(callback)
        val id = UUID.randomUUID().toString()
        owners[id] = owner
        return ExecutionLease { release(id) }
    }

    @Synchronized private fun release(id: String) {
        owners.remove(id)
        cancelDisallowed()
        if (owners.isEmpty()) connectivity.unregisterNetworkCallback(callback)
    }

    fun hasLocalLease(): Boolean = owners.values.any {
        it == ExecutionOwner.Foreground || it == ExecutionOwner.LocalJob
    }

    fun permits(task: DownloadTask): Boolean = task.attemptId !in blocked && !task.userPaused && owners.values.any {
        it == ExecutionOwner.Foreground ||
            (task.wifiOnly && it == ExecutionOwner.WifiJob) || (!task.wifiOnly && it == ExecutionOwner.UnrestrictedJob)
    } && DownloadNetworkPolicy.allows(task.wifiOnly, status())

    fun status(): NetworkStatus {
        val caps = connectivity.activeNetwork?.let(connectivity::getNetworkCapabilities)
        return NetworkStatus(
            caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true,
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true,
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true,
            connectivity.isActiveNetworkMetered
        )
    }

    fun client(task: DownloadTask): OkHttpClient {
        if (!permits(task)) throw IOException("No permitted download execution/network")
        val network = connectivity.activeNetwork ?: throw IOException("Network unavailable")
        val caps = connectivity.getNetworkCapabilities(network) ?: throw IOException("Network unavailable")
        val calls = ConcurrentHashMap.newKeySet<okhttp3.Call>()
        val builder = baseClient.newBuilder().eventListener(object : okhttp3.EventListener() {
            override fun callStart(call: okhttp3.Call) {
                calls += call
                if (!permits(task) || connectivity.activeNetwork != network) call.cancel()
            }

            override fun callEnd(call: okhttp3.Call) {
                calls -= call
            }

            override fun callFailed(call: okhttp3.Call, ioe: IOException) {
                calls -= call
            }
        }).dispatcher(Dispatcher()).connectionPool(ConnectionPool())
            .followRedirects(false).followSslRedirects(false)
        // Binding physical interfaces under an active VPN would bypass it. Unrestricted VPN work uses the default route.
        if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
            builder.socketFactory(network.socketFactory).dns { host -> network.getAllByName(host).toList() }
        }
        builder.addInterceptor { chain ->
            if (!permits(task) || connectivity.activeNetwork != network) throw IOException("Download network changed")
            val original = chain.request()
            if (UpstreamUrlPolicy.media(original.url.toString()) == null) throw IOException("Unsupported media URL")
            val position =
                original.header("Range")?.substringAfter("bytes=")?.substringBefore('-')?.toLongOrNull() ?: 0L
            val request = original.newBuilder().header("Referer", UpstreamUrlPolicy.REFERER)
                .header("User-Agent", UpstreamRequestProfile.USER_AGENT).apply {
                    if (position > 0) (task.mediaEtag ?: task.mediaLastModified)?.let { header("If-Range", it) }
                }.build()
            val response = chain.proceed(request)
            try {
                if (request.method == "GET") {
                    ResumeValidator.validate(
                        MediaIdentity(task.totalBytes, task.mediaEtag, task.mediaLastModified, task.acceptsRanges),
                        position,
                        response.code,
                        response.header("Content-Range"),
                        response.header("ETag"),
                        response.header("Last-Modified")
                    )
                    if (response.code !in listOf(200, 206)) throw IOException("Media HTTP ${response.code}")
                }
                response
            } catch (failure: Exception) {
                response.close()
                throw failure
            }
        }
        val client = builder.build()
        clients.put(task.attemptId, Connection(task, network, client, calls))?.close()
        return client
    }

    fun cancel(attemptId: String) {
        clients.remove(attemptId)?.close()
    }

    fun block(attemptId: String) {
        blocked += attemptId
        cancel(attemptId)
    }

    fun unblock(attemptId: String) {
        blocked -= attemptId
    }

    private fun cancelDisallowed() {
        clients.filterValues { !permits(it.task) || it.network != connectivity.activeNetwork }.keys.forEach(::cancel)
    }

    fun cancelAll() {
        clients.keys.toList().forEach(::cancel)
    }
}
