package dev.sctvdl.app

import android.app.Application
import android.content.Context
import coil3.ImageLoader
import coil3.SingletonImageLoader
import dagger.hilt.android.HiltAndroidApp
import dev.sctvdl.app.platform.CoverImageLoaderOwner
import javax.inject.Inject

@HiltAndroidApp
class SctvApplication :
    Application(),
    SingletonImageLoader.Factory {
    @Inject lateinit var coverImages: CoverImageLoaderOwner

    override fun newImageLoader(context: Context): ImageLoader = coverImages.loaders.value
}
