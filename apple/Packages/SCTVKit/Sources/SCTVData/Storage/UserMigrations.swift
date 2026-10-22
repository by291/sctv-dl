import GRDB

enum UserMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("user-v1") { db in
            try db.create(table: "favourites") { table in
                table.column("programme_id", .text).primaryKey()
                table.column("created_at", .double).notNull()
            }
            try db.create(table: "preferences") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
                table.column("edit_revision", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "history") { table in
                table.column("programme_id", .text).notNull()
                table.column("date_id", .text).notNull()
                table.column("content_id", .text).notNull()
                table.column("title", .text).notNull()
                table.column("programme_name", .text).notNull()
                table.column("cover", .text)
                table.column("position_ms", .integer).notNull()
                table.column("duration_ms", .integer)
                table.column("completed", .boolean).notNull()
                table.column("updated_at", .double).notNull()
                table.primaryKey(["programme_id", "date_id", "content_id"])
            }
        }
        migrator.registerMigration("user-v2") { db in
            try db.create(index: "history_recent", on: "history", columns: ["updated_at"])
        }
        migrator.registerMigration("user-v3") { db in
            try db.alter(table: "history") { table in
                table.add(column: "broadcast_date", .text).notNull().defaults(to: "")
            }
            try db.create(table: "history_sessions") { table in
                table.column("programme_id", .text).notNull()
                table.column("date_id", .text).notNull()
                table.column("content_id", .text).notNull()
                table.column("session_id", .text).notNull().unique()
                table.column("payload", .blob).notNull()
                table.column("sequence", .integer).notNull()
                table.primaryKey(["programme_id", "date_id", "content_id"])
            }
        }
        return migrator
    }
}
