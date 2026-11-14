import Foundation
import GRDB

public enum ConsumerError: Error, Equatable, LocalizedError {
    case blankConsumer
    case noSuchRecord(UUID)
    case noSuchVersion(UUID, Int)

    public var errorDescription: String? {
        switch self {
        case .blankConsumer: return "The consumer name must not be empty."
        case .noSuchRecord(let id): return "There is no exported record with id \(id.uuidString)."
        case .noSuchVersion(let id, let version): return "Record \(id.uuidString) has no version \(version)."
        }
    }
}

/// Remembers which record versions an agent or script has already picked up.
public struct ConsumerStore: Sendable {
    private let database: LorreDatabase

    public init(database: LorreDatabase) {
        self.database = database
    }

    /// Marks the given version (default: the latest exported one) as processed by this consumer.
    /// Marking twice is fine. Throws when the record or version does not exist, or the name is blank.
    @discardableResult
    public func markProcessed(
        recordId: UUID, version: Int? = nil, consumer: String, now: Date = Date()
    ) throws -> ConsumerCursor {
        let name = consumer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ConsumerError.blankConsumer }
        return try database.queue.write { db in
            let latest = try Int.fetchOne(db, sql: """
                SELECT MAX(version) FROM recordExport WHERE conversationId = ?
                """, arguments: [recordId.uuidString])
            guard let latest else { throw ConsumerError.noSuchRecord(recordId) }
            let target = version ?? latest
            let exists = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM recordExport WHERE conversationId = ? AND version = ?)
                """, arguments: [recordId.uuidString, target]) ?? false
            guard exists else { throw ConsumerError.noSuchVersion(recordId, target) }
            let cursor = ConsumerCursor(
                consumerName: name, conversationId: recordId, recordVersion: target, processedAt: now
            )
            try cursor.save(db)
            return cursor
        }
    }

    public func cursors(consumer: String) throws -> [ConsumerCursor] {
        try database.queue.read { db in
            try ConsumerCursor.fetchAll(db, sql: """
                SELECT * FROM consumerCursor WHERE consumerName = ?
                 ORDER BY conversationId, recordVersion
                """, arguments: [consumer.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }
}
