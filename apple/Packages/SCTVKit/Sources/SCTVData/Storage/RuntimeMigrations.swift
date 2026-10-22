import GRDB

enum RuntimeMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("runtime-v1") { db in
            try db.create(table: "programme_snapshots") { table in
                table.column("resource_key", .text).primaryKey()
                table.column("payload", .blob).notNull()
                table.column("revision", .text).notNull()
                table.column("fetched_at", .double).notNull()
            }
            try db.create(table: "download_tasks") { table in
                table.column("task_id", .text).primaryKey()
                table.column("attempt_id", .text).notNull()
                table.column("programme_id", .text).notNull()
                table.column("date_id", .text).notNull()
                table.column("content_id", .text).notNull()
                table.column("quality", .text).notNull()
                table.column("state", .text).notNull()
                table.column("relative_path", .text)
                table.column("payload", .blob).notNull()
                table.column("updated_at", .double).notNull()
            }
            try db.create(table: "download_attempts") { table in
                table.column("attempt_id", .text).primaryKey()
                table.column("task_id", .text).notNull().references(
                    "download_tasks", onDelete: .cascade)
                table.column("system_task_id", .integer)
                table.column("resume_reference", .text)
                table.column("staging_path", .text)
                table.column("updated_at", .double).notNull()
            }
            try db.create(
                index: "download_attempt_task", on: "download_attempts", columns: ["task_id"])
        }
        DownloadMigrations.register(on: &migrator)
        return migrator
    }
}
