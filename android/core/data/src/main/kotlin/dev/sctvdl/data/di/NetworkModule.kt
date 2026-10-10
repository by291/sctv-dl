package dev.sctvdl.data.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dev.sctvdl.data.network.UpstreamUrlPolicy
import dev.sctvdl.data.programmes.remote.ProgrammeApi
import java.io.IOException
import java.util.concurrent.TimeUnit
import javax.inject.Singleton
import okhttp3.OkHttpClient
import retrofit2.Retrofit

@Module
@InstallIn(SingletonComponent::class)
internal object NetworkModule {
    @Provides @Singleton
    fun client(): OkHttpClient = OkHttpClient.Builder().followRedirects(
        false
    ).followSslRedirects(
        false
    ).connectTimeout(15, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS).build()

    @Provides @Singleton
    fun api(client: OkHttpClient): ProgrammeApi = Retrofit.Builder().baseUrl(
        "https://gw.scgchc.com/"
    ).client(client).build().create(ProgrammeApi::class.java)

    @Provides @Singleton @CoverImageClient
    fun coverClient(client: OkHttpClient): OkHttpClient = client.newBuilder().addInterceptor { chain ->
        val request = chain.request()
        if (UpstreamUrlPolicy.cover(request.url.toString()) == null) {
            throw IOException("Unsupported cover URL")
        }
        chain.proceed(request)
    }.build()
}
