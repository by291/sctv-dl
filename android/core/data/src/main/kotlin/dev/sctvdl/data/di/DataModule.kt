package dev.sctvdl.data.di

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.room.Room
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dev.sctvdl.data.downloads.AndroidDownloadGateway
import dev.sctvdl.data.downloads.DownloadStore
import dev.sctvdl.data.downloads.MediaPreflight
import dev.sctvdl.data.downloads.MediaProbe
import dev.sctvdl.data.downloads.OkHttpMediaProbe
import dev.sctvdl.data.downloads.PlatformDownloadGateway
import dev.sctvdl.data.downloads.RoomDownloadStore
import dev.sctvdl.data.downloads.SystemDownloadRepository
import dev.sctvdl.data.local.RoomSnapshotStore
import dev.sctvdl.data.local.SctvDatabase
import dev.sctvdl.data.network.ProgrammeApi
import dev.sctvdl.data.network.RetrofitProgrammeSource
import dev.sctvdl.data.network.UpstreamParser
import dev.sctvdl.data.repository.DataStoreSettingsRepository
import dev.sctvdl.data.repository.LocalFavouriteRepository
import dev.sctvdl.data.repository.OfflineProgrammeRepository
import dev.sctvdl.data.repository.ProgrammeSource
import dev.sctvdl.data.repository.SnapshotStore
import dev.sctvdl.domain.DownloadRepository
import dev.sctvdl.domain.FavouriteRepository
import dev.sctvdl.domain.ProgrammeRepository
import dev.sctvdl.domain.SettingsRepository
import java.time.Clock
import java.util.concurrent.TimeUnit
import javax.inject.Qualifier
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import okhttp3.OkHttpClient
import retrofit2.Retrofit

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class IoDispatcher

@Module
@InstallIn(SingletonComponent::class)
object DataModule {
    @Provides @Singleton
    fun database(@ApplicationContext context: Context): SctvDatabase = Room.databaseBuilder(
        context,
        SctvDatabase::class.java,
        "sctv-metadata.db"
    ).build()

    @Provides @Singleton
    fun preferences(@ApplicationContext context: Context): DataStore<Preferences> =
        PreferenceDataStoreFactory.create(produceFile = {
            context.preferencesDataStoreFile("settings")
        })

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

    @Provides fun parser() = UpstreamParser()

    @Provides fun clock(): Clock = Clock.systemUTC()

    @Provides @IoDispatcher
    fun dispatcher(): CoroutineDispatcher = Dispatchers.IO

    @Provides fun source(source: RetrofitProgrammeSource): ProgrammeSource = source

    @Provides fun snapshots(store: RoomSnapshotStore): SnapshotStore = store

    @Provides @Singleton
    fun programmes(
        source: ProgrammeSource,
        snapshots: SnapshotStore,
        parser: UpstreamParser,
        clock: Clock,
        @IoDispatcher dispatcher: CoroutineDispatcher
    ): ProgrammeRepository = OfflineProgrammeRepository(
        source,
        snapshots,
        parser,
        clock,
        dispatcher
    )

    @Provides @Singleton
    fun favourites(repository: LocalFavouriteRepository): FavouriteRepository = repository

    @Provides @Singleton
    fun settings(repository: DataStoreSettingsRepository): SettingsRepository = repository

    @Provides @Singleton
    fun downloadStore(store: RoomDownloadStore): DownloadStore = store

    @Provides @Singleton
    fun downloadGateway(gateway: AndroidDownloadGateway): PlatformDownloadGateway = gateway

    @Provides fun probe(probe: OkHttpMediaProbe): MediaProbe = probe

    @Provides fun preflight(probe: MediaProbe) = MediaPreflight(probe)

    @Provides @Singleton
    fun downloads(
        store: DownloadStore,
        gateway: PlatformDownloadGateway,
        preflight: MediaPreflight,
        clock: Clock,
        @IoDispatcher dispatcher: CoroutineDispatcher
    ): DownloadRepository = SystemDownloadRepository(store, gateway, preflight, clock, dispatcher)
}
