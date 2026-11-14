import Foundation
import GRDB

/// Database conformance shared by all stored domain types.
/// UUIDs are stored as uppercase strings so they match the folder names of the legacy store
/// and stay readable in the `sqlite3` shell.
protocol LorreRecord: FetchableRecord, PersistableRecord {}

extension LorreRecord {
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }
}

extension Conversation: LorreRecord { public static let databaseTableName = "conversation" }
extension Person: LorreRecord { public static let databaseTableName = "person" }
extension Participant: LorreRecord { public static let databaseTableName = "participant" }
extension Track: LorreRecord { public static let databaseTableName = "track" }
extension TranscriptVersion: LorreRecord { public static let databaseTableName = "transcriptVersion" }
extension Segment: LorreRecord { public static let databaseTableName = "segment" }
extension Outcome: LorreRecord { public static let databaseTableName = "outcome" }
extension RecordExport: LorreRecord { public static let databaseTableName = "recordExport" }
extension ConsumerCursor: LorreRecord { public static let databaseTableName = "consumerCursor" }
