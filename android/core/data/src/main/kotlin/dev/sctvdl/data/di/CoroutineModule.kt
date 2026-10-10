package dev.sctvdl.data.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import java.time.Clock
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

@Module
@InstallIn(SingletonComponent::class)
internal object CoroutineModule {
    @Provides fun clock(): Clock = Clock.systemUTC()

    @Provides @IoDispatcher
    fun dispatcher(): CoroutineDispatcher = Dispatchers.IO
}
