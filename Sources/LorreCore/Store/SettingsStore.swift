import Foundation
import GRDB

/// Small key-value settings of the rebuilt app, kept in the database so the CLI sees them too.
public struct SettingsStore: Sendable {
    public enum Key: String, Sendable {
        /// Folder the records are written to.
        case exportFolder
        /// How the user is called in transcripts and records.
        case userName
        /// Whether the audio of a conversation is removed once it has been approved.
        case deleteAudioAfterApproval
    }

    let database: LorreDatabase

    public init(database: LorreDatabase) {
        self.database = database
    }

    public func string(_ key: Key) throws -> String? {
        try database.queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key.rawValue])
        }
    }

    /// Stores the value; nil or an empty value removes the setting.
    public func set(_ value: String?, for key: Key) throws {
        try database.queue.write { db in
            if let value, !value.isEmpty {
                try db.execute(
                    sql: "INSERT INTO setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                    arguments: [key.rawValue, value]
                )
            } else {
                try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [key.rawValue])
            }
        }
    }

    /// Where records go: the chosen folder, or `~/Documents/Lorre` by default.
    public func exportFolder() throws -> URL {
        if let path = try string(.exportFolder) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return Self.defaultExportFolder()
    }

    public static func defaultExportFolder() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        return documents.appendingPathComponent("Lorre", isDirectory: true)
    }

    public func userName() throws -> String {
        try string(.userName) ?? NSFullUserName().split(separator: " ").first.map(String.init) ?? "Me"
    }
}
