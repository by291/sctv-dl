package dev.sctvdl.app

import android.app.Application
import android.content.Context
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import dagger.hilt.android.HiltAndroidApp
import dev.sctvdl.data.di.CoverImageClient
import javax.inject.Inject
import okhttp3.OkHttpClient

@HiltAndroidApp
class SctvApplication :
    Application(),
    SingletonImageLoader.Factory {
    @Inject @CoverImageClient
    lateinit var httpClient: OkHttpClient

    override fun newImageLoader(context: Context): ImageLoader = ImageLoader.Builder(context)
        .components {
            add(
                OkHttpNetworkFetcherFactory(callFactory = {
                    httpClient
                })
            )
        }.build()
}
