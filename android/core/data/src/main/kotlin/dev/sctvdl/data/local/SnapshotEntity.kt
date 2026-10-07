package dev.sctvdl.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

// A row marks a successful snapshot, including an empty array.
@Entity(tableName = "snapshots")
data class SnapshotEntity(@PrimaryKey val key: String, val payload: String, val updatedAt: Long)
