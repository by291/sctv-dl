package dev.sctvdl.data.database

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

internal object RuntimeMigrations {
    val OneToTwo = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE downloads ADD COLUMN owner TEXT NOT NULL DEFAULT 'LegacySystem'")
            db.execSQL("ALTER TABLE downloads ADD COLUMN attemptId TEXT NOT NULL DEFAULT ''")
            db.execSQL("ALTER TABLE downloads ADD COLUMN revision INTEGER NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE downloads ADD COLUMN selectionJson TEXT DEFAULT NULL")
            db.execSQL("ALTER TABLE downloads ADD COLUMN cacheKey TEXT DEFAULT NULL")
            db.execSQL("ALTER TABLE downloads ADD COLUMN publicationUri TEXT DEFAULT NULL")
            db.execSQL("ALTER TABLE downloads ADD COLUMN publicationStarted INTEGER NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE downloads ADD COLUMN cacheComplete INTEGER NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE downloads ADD COLUMN cleanupPending INTEGER NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE downloads ADD COLUMN userPaused INTEGER NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE downloads ADD COLUMN mediaEtag TEXT DEFAULT NULL")
            db.execSQL("ALTER TABLE downloads ADD COLUMN mediaLastModified TEXT DEFAULT NULL")
            db.execSQL("ALTER TABLE downloads ADD COLUMN acceptsRanges INTEGER NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE downloads ADD COLUMN mediaChecked INTEGER NOT NULL DEFAULT 0")
            db.execSQL("UPDATE downloads SET attemptId = id")
        }
    }
}
