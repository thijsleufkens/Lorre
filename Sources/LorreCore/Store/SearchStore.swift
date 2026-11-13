import Foundation
import GRDB

public struct SearchHit: Equatable, Sendable {
    public var conversationId: UUID
    public var conversationTitle: String
    public var segmentId: UUID
    public var startMs: Int
    /// The matching text with the matched words between `[` and `]`.
    public var snippet: String
}

/// Full-text search over the current transcripts.
public struct SearchStore: Sendable {
    let database: LorreDatabase

    public init(database: LorreDatabase) {
        self.database = database
    }

    /// Finds segments containing every word of the query; the last word may be a prefix of a longer one.
    /// A query without any searchable word returns nothing.
    public func search(_ query: String, limit: Int = 50) throws -> [SearchHit] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }
        return try database.queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT conversation.id AS conversationId, conversation.title AS title,
                       segment.id AS segmentId, segment.startMs AS startMs,
                       snippet(segmentSearch, 0, '[', ']', '…', 16) AS snippet
                  FROM segmentSearch
                  JOIN segment ON segment.rowid = segmentSearch.rowid
                  JOIN transcriptVersion ON transcriptVersion.id = segment.transcriptVersionId
                  JOIN conversation ON conversation.id = transcriptVersion.conversationId
                 WHERE segmentSearch MATCH ? AND transcriptVersion.isCurrent = 1
                 ORDER BY conversation.startedAt DESC, segment.startMs
                 LIMIT ?
                """, arguments: [pattern, limit])
            return rows.compactMap { row in
                guard let conversationId = UUID(uuidString: row["conversationId"]),
                      let segmentId = UUID(uuidString: row["segmentId"]) else { return nil }
                return SearchHit(
                    conversationId: conversationId,
                    conversationTitle: row["title"],
                    segmentId: segmentId,
                    startMs: row["startMs"],
                    snippet: row["snippet"]
                )
            }
        }
    }
}
