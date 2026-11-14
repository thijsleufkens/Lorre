import Foundation
import GRDB

/// One exported record, latest version.
public struct RecordListing: Codable, Equatable, Sendable {
    public var recordId: UUID
    public var recordVersion: Int
    public var status: RecordStatus
    public var title: String
    public var type: ConversationType
    public var startedAt: Date
    public var approvedAt: Date?
    /// The JSON file.
    public var path: String

    public init(
        recordId: UUID, recordVersion: Int, status: RecordStatus, title: String, type: ConversationType,
        startedAt: Date, approvedAt: Date? = nil, path: String
    ) {
        self.recordId = recordId
        self.recordVersion = recordVersion
        self.status = status
        self.title = title
        self.type = type
        self.startedAt = startedAt
        self.approvedAt = approvedAt
        self.path = path
    }
}

public enum RecordCatalogError: Error, Equatable, LocalizedError {
    case noRecordWithPrefix(String)
    case ambiguousPrefix(String, count: Int)
    case fileMissing(path: String)
    case unreadable(path: String)

    public var errorDescription: String? {
        switch self {
        case .noRecordWithPrefix(let text):
            return "No record with an id starting with \(text)."
        case .ambiguousPrefix(let text, let count):
            return "\(count) records start with \(text); give more characters."
        case .fileMissing(let path):
            return "The record file is gone: \(path). Open the conversation in Lorre and finish it again to write it anew."
        case .unreadable(let path):
            return "The record file could not be read: \(path)."
        }
    }
}

/// Reads the records Lorre has exported, for agents and the command line.
public struct RecordCatalog: Sendable {
    private let database: LorreDatabase

    public init(database: LorreDatabase) {
        self.database = database
    }

    /// The latest exported version of every conversation that has one, newest conversation first.
    /// `status` filters; `newFor` leaves out records this consumer already marked at that version.
    public func list(status: RecordStatus? = nil, newFor consumer: String? = nil) throws -> [RecordListing] {
        try database.queue.read { db in
            var sql = """
                SELECT recordExport.conversationId AS conversationId, recordExport.version AS version,
                       recordExport.status AS status, recordExport.approvedAt AS approvedAt,
                       recordExport.path AS path, conversation.title AS title,
                       conversation.type AS type, conversation.startedAt AS startedAt
                  FROM recordExport
                  JOIN conversation ON conversation.id = recordExport.conversationId
                 WHERE recordExport.version = (
                         SELECT MAX(version) FROM recordExport AS latest
                          WHERE latest.conversationId = recordExport.conversationId)
                """
            var arguments: [any DatabaseValueConvertible] = []
            if let status {
                sql += " AND recordExport.status = ?"
                arguments.append(status.rawValue)
            }
            if let consumer {
                sql += """

                     AND NOT EXISTS (
                         SELECT 1 FROM consumerCursor
                          WHERE consumerCursor.consumerName = ?
                            AND consumerCursor.conversationId = recordExport.conversationId
                            AND consumerCursor.recordVersion >= recordExport.version)
                    """
                arguments.append(consumer.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            sql += " ORDER BY conversation.startedAt DESC, conversation.id"
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).compactMap { row in
                guard let id = UUID(uuidString: row["conversationId"]),
                      let status = RecordStatus(rawValue: row["status"]),
                      let type = ConversationType(rawValue: row["type"])
                else { return nil }
                return RecordListing(
                    recordId: id, recordVersion: row["version"], status: status, title: row["title"],
                    type: type, startedAt: row["startedAt"], approvedAt: row["approvedAt"], path: row["path"]
                )
            }
        }
    }

    /// The record as stored on disk at its latest path; throws a clear error when the file is gone.
    public func record(_ recordId: UUID) throws -> MeetingRecord {
        guard let listing = try list().first(where: { $0.recordId == recordId }) else {
            throw RecordCatalogError.noRecordWithPrefix(recordId.uuidString)
        }
        guard FileManager.default.fileExists(atPath: listing.path) else {
            throw RecordCatalogError.fileMissing(path: listing.path)
        }
        do {
            return try MeetingRecord.decoder().decode(
                MeetingRecord.self, from: Data(contentsOf: URL(fileURLWithPath: listing.path))
            )
        } catch {
            throw RecordCatalogError.unreadable(path: listing.path)
        }
    }

    /// Finds the record whose id is, or starts with, the given text.
    public static func resolve(_ text: String, in listings: [RecordListing]) throws -> RecordListing {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !needle.isEmpty else { throw RecordCatalogError.noRecordWithPrefix(text) }
        let matches = listings.filter { $0.recordId.uuidString.hasPrefix(needle) }
        switch matches.count {
        case 1: return matches[0]
        case 0: throw RecordCatalogError.noRecordWithPrefix(text)
        default: throw RecordCatalogError.ambiguousPrefix(text, count: matches.count)
        }
    }
}
