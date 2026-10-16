package uz.shs.better_player_plus

import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/** Application playback rejects every redirect; range reads remain streaming. */
internal object StrictMediaHttpClient {
    fun create(): OkHttpClient = OkHttpClient.Builder()
        .followRedirects(false)
        .followSslRedirects(false)
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()
}
