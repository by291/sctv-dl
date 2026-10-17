package dev.sctvdl.data.di

import android.content.Context
import androidx.room.Room
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.data.database.SctvUserDatabase
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
internal object DatabaseModule {
    @Provides @Singleton
    fun users(@ApplicationContext context: Context): SctvUserDatabase = Room.databaseBuilder(
        context,
        SctvUserDatabase::class.java,
        "sctv-user.db"
    ).build()

    @Provides @Singleton
    fun database(@ApplicationContext context: Context): SctvDatabase = Room.databaseBuilder(
        context,
        SctvDatabase::class.java,
        "sctv-metadata.db"
    ).build()
}
