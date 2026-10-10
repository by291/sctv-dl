package dev.sctvdl.data.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dev.sctvdl.data.favourites.RoomFavouriteRepository
import dev.sctvdl.data.programmes.CachedProgrammeRepository
import dev.sctvdl.data.programmes.local.RoomSnapshotStore
import dev.sctvdl.data.programmes.local.SnapshotStore
import dev.sctvdl.data.programmes.remote.ProgrammeRemoteDataSource
import dev.sctvdl.data.programmes.remote.ProgrammeResponseParser
import dev.sctvdl.data.programmes.remote.RetrofitProgrammeRemoteDataSource
import dev.sctvdl.domain.repository.FavouriteRepository
import dev.sctvdl.domain.repository.ProgrammeRepository
import java.time.Clock
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineDispatcher

@Module
@InstallIn(SingletonComponent::class)
internal object ProgrammesModule {
    @Provides fun parser() = ProgrammeResponseParser()

    @Provides fun source(source: RetrofitProgrammeRemoteDataSource): ProgrammeRemoteDataSource = source

    @Provides fun snapshots(store: RoomSnapshotStore): SnapshotStore = store

    @Provides @Singleton
    fun programmes(
        source: ProgrammeRemoteDataSource,
        snapshots: SnapshotStore,
        parser: ProgrammeResponseParser,
        clock: Clock,
        @IoDispatcher dispatcher: CoroutineDispatcher
    ): ProgrammeRepository = CachedProgrammeRepository(
        source,
        snapshots,
        parser,
        clock,
        dispatcher
    )

    @Provides @Singleton
    fun favourites(repository: RoomFavouriteRepository): FavouriteRepository = repository
}
