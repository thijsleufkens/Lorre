import Foundation
import GRDB

/// The SQLite database behind Lorre. Opening it brings the schema up to date.
public final class LorreDatabase: Sendable {
    let queue: DatabaseQueue

    /// Opens (and if needed creates) the database file.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        queue = try DatabaseQueue(path: url.path(percentEncoded: false))
        try Schema.migrator.migrate(queue)
    }

    private init(queue: DatabaseQueue, migrate: Bool = true) throws {
        self.queue = queue
        if migrate { try Schema.migrator.migrate(queue) }
    }

    /// An in-memory database migrated only up to the given schema version, to test upgrades.
    static func inMemory(upTo migration: String) throws -> LorreDatabase {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue, upTo: migration)
        return try LorreDatabase(queue: queue, migrate: false)
    }

    /// Brings a partially migrated database up to date.
    func migrateToLatest() throws {
        try Schema.migrator.migrate(queue)
    }

    /// A private database that lives only in memory, for tests.
    public static func inMemory() throws -> LorreDatabase {
        try LorreDatabase(queue: DatabaseQueue())
    }

    /// Names of the tables in the database, for diagnostics and tests.
    public func tableNames() throws -> Set<String> {
        try queue.read { db in
            try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }
    }
}
