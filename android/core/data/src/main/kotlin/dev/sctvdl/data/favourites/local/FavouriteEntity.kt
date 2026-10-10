package dev.sctvdl.data.favourites.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "favourites")
internal data class FavouriteEntity(@PrimaryKey val id: String)
