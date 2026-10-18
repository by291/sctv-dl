package dev.sctvdl.data.history.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "viewing_history")
internal data class HistoryEntity(
    @PrimaryKey val key: String,
    val targetJson: String,
    val positionMs: Long,
    val durationMs: Long?,
    val viewedAt: Long,
    val completed: Boolean
)

@Entity(tableName = "history_sessions")
internal data class HistorySessionEntity(
    @PrimaryKey val key: String,
    val deletionGeneration: Long = 0,
    val sessionGeneration: Long = 0
)

@Entity(tableName = "user_metadata")
internal data class UserMetadata(@PrimaryKey val key: String, val value: String)
