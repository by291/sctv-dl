package dev.sctvdl.app.platform

import android.content.Context
import coil3.ImageLoader
import coil3.disk.DiskCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.sctvdl.data.di.CoverImageClient
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okio.Path.Companion.toOkioPath

/** Each generation owns its cache and writers; retired requests cannot populate its replacement. */
@Singleton
class CoverImageLoaderOwner @Inject constructor(
    @ApplicationContext private val context: Context,
    @CoverImageClient private val client: OkHttpClient
) {
    private val preferences = context.getSharedPreferences("image_cache_generation", Context.MODE_PRIVATE)
    private val root = context.cacheDir.resolve("covers")
    private var generation = preferences.getString("generation", "initial") ?: "initial"
    private val lock = Mutex()
    private val mutableLoaders = MutableStateFlow(create(generation))
    val loaders = mutableLoaders.asStateFlow()

    suspend fun clearCache() = withContext(Dispatchers.IO) {
        lock.withLock {
            val old = mutableLoaders.value
            val next = UUID.randomUUID().toString()
            check(preferences.edit().putString("generation", next).commit()) { "Cannot persist image cache generation" }
            val replacement = create(next)
            generation = next
            old.shutdown()
            old.diskCache?.shutdown()
            mutableLoaders.value = replacement
            // DiskCache.shutdown aborts old editors. Only image directories are deleted.
            root.listFiles()?.filter { it.name != next }?.forEach { check(it.deleteRecursively()) }
            val legacyCache = context.cacheDir.resolve("image_cache")
            if (legacyCache.exists()) check(legacyCache.deleteRecursively())
        }
    }

    private fun create(generation: String): ImageLoader = ImageLoader.Builder(context)
        .diskCache { DiskCache.Builder().directory(root.resolve(generation).toOkioPath()).build() }
        .components { add(OkHttpNetworkFetcherFactory(callFactory = { client })) }
        .build()
}
