@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.data.di

import android.content.Context
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dev.sctvdl.data.downloads.DownloadManagerRepository
import dev.sctvdl.data.downloads.DownloadTransitions
import dev.sctvdl.data.downloads.ManagedDownloadRepository
import dev.sctvdl.data.downloads.local.DownloadStore
import dev.sctvdl.data.downloads.local.LegacyDownloadStore
import dev.sctvdl.data.downloads.local.RoomDownloadStore
import dev.sctvdl.data.downloads.managed.DownloadNetworkAccess
import dev.sctvdl.data.downloads.managed.ManagedDownloadControl
import dev.sctvdl.data.downloads.managed.ManagedTransferGateway
import dev.sctvdl.data.downloads.managed.ManagedTransferRuntime
import dev.sctvdl.data.downloads.managed.Media3TransferGateway
import dev.sctvdl.data.downloads.managed.NetworkBoundMediaSource
import dev.sctvdl.data.downloads.platform.DownloadManagerGateway
import dev.sctvdl.data.downloads.platform.MediaStoreDownloadFiles
import dev.sctvdl.data.downloads.platform.PlatformDownloadGateway
import dev.sctvdl.data.downloads.platform.PublicDownloadFiles
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
    fun managedGateway(@ApplicationContext context: Context, access: DownloadNetworkAccess): ManagedTransferGateway =
        Media3TransferGateway(
            context,
            context.noBackupFilesDir.resolve("managed-media"),
            StandaloneDatabaseProvider(context),
            "Managed"
        ) { task ->
            DataSource.Factory { NetworkBoundMediaSource(task, access) }
        }

    @Provides @Singleton
    fun managedControl(runtime: ManagedTransferRuntime): ManagedDownloadControl = runtime

    @Provides @Singleton
    fun publicFiles(files: MediaStoreDownloadFiles): PublicDownloadFiles = files

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
        @IoDispatcher dispatcher: CoroutineDispatcher,
        control: ManagedDownloadControl,
        files: PublicDownloadFiles,
        consents: DownloadFileConsentRegistry,
        transitions: DownloadTransitions
    ): DownloadRepository = ManagedDownloadRepository(
        store,
        DownloadManagerRepository(LegacyDownloadStore(store), gateway, preflight, clock, dispatcher),
        control,
        files,
        consents,
        transitions,
        clock
    )
}
