package dev.sctvdl.app.platform

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dev.sctvdl.domain.repository.ProgrammeRepository
import dev.sctvdl.domain.repository.StorageMaintenance
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
internal object StorageModule {
    @Provides @Singleton
    fun storage(programmes: ProgrammeRepository, images: CoverImageLoaderOwner): StorageMaintenance =
        AppStorageMaintenance(programmes::clearCache, images::clearCache)
}
