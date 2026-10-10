package dev.sctvdl.data.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dev.sctvdl.data.downloads.DownloadManagerRepository
import dev.sctvdl.data.downloads.local.DownloadStore
import dev.sctvdl.data.downloads.local.RoomDownloadStore
import dev.sctvdl.data.downloads.platform.DownloadManagerGateway
import dev.sctvdl.data.downloads.platform.PlatformDownloadGateway
import dev.sctvdl.data.downloads.preflight.MediaPreflight
import dev.sctvdl.data.downloads.preflight.MediaProbe
import dev.sctvdl.data.downloads.preflight.OkHttpMediaProbe
import dev.sctvdl.domain.repository.DownloadRepository
import java.time.Clock
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineDispatcher

@Module
@InstallIn(SingletonComponent::class)
internal object DownloadsModule {
    @Provides @Singleton
    fun downloadStore(store: RoomDownloadStore): DownloadStore = store

    @Provides @Singleton
    fun downloadGateway(gateway: DownloadManagerGateway): PlatformDownloadGateway = gateway

    @Provides fun probe(probe: OkHttpMediaProbe): MediaProbe = probe

    @Provides fun preflight(probe: MediaProbe) = MediaPreflight(probe)

    @Provides @Singleton
    fun downloads(
        store: DownloadStore,
        gateway: PlatformDownloadGateway,
        preflight: MediaPreflight,
        clock: Clock,
        @IoDispatcher dispatcher: CoroutineDispatcher
    ): DownloadRepository = DownloadManagerRepository(store, gateway, preflight, clock, dispatcher)
}
