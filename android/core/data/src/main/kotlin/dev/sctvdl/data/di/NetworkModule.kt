package dev.sctvdl.data.di

import android.content.Context
import android.os.Build
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dev.sctvdl.data.network.InstallationDeviceId
import dev.sctvdl.data.network.ProgrammeHeadersInterceptor
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
    fun api(client: OkHttpClient, @ApplicationContext context: Context): ProgrammeApi {
        // Shared preferences are excluded by the settings-only backup rules, keeping IDs installation-local.
        val identity = InstallationDeviceId(context.getSharedPreferences("upstream_client", Context.MODE_PRIVATE))
        val headers = ProgrammeHeadersInterceptor(
            deviceId = identity::getOrCreate,
            brand = Build.BRAND,
            model = Build.MODEL,
            systemVersion = Build.VERSION.RELEASE
        )
        val programmeClient = client.newBuilder().addNetworkInterceptor(headers).build()

        return Retrofit.Builder().baseUrl("https://gw.scgchc.com/")
            .client(programmeClient).build().create(ProgrammeApi::class.java)
    }

    @Provides @Singleton @CoverImageClient
    fun coverClient(client: OkHttpClient): OkHttpClient = client.newBuilder().addInterceptor { chain ->
        val request = chain.request()
        if (UpstreamUrlPolicy.cover(request.url.toString()) == null) {
            throw IOException("Unsupported cover URL")
        }
        chain.proceed(request)
    }.build()
}
