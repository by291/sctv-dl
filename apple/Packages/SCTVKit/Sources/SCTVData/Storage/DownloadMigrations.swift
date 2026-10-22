import GRDB

enum DownloadMigrations {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("runtime-v2-download-guards") { db in
            try db.alter(table: "download_tasks") { table in
                table.add(column: "revision", .integer).notNull().defaults(to: 0)
                table.add(column: "native_session", .text)
                table.add(column: "native_task_id", .integer)
            }
            try db.execute(
                sql: """
                    CREATE UNIQUE INDEX active_download_content_quality
                    ON download_tasks (programme_id, date_id, content_id, quality)
                    WHERE state IN ('queued', 'transferring', 'paused', 'publishing', 'interrupted', 'transferFailed', 'publicationFailed')
                    """)
        }
    }
}
