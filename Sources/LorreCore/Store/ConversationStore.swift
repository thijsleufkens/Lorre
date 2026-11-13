import Foundation
import GRDB

/// A conversation with the numbers a list needs, fetched in one query.
public struct ConversationSummary: Equatable, Sendable {
    public var conversation: Conversation
    public var participantNames: [String]
    /// Segments in the current transcript version.
    public var segmentCount: Int
    public var proposedOutcomes: Int
    public var approvedOutcomes: Int

    public init(
        conversation: Conversation,
        participantNames: [String],
        segmentCount: Int,
        proposedOutcomes: Int,
        approvedOutcomes: Int
    ) {
        self.conversation = conversation
        self.participantNames = participantNames
        self.segmentCount = segmentCount
        self.proposedOutcomes = proposedOutcomes
        self.approvedOutcomes = approvedOutcomes
    }
}

public struct ConversationStore: Sendable {
    let database: LorreDatabase

    public init(database: LorreDatabase) {
        self.database = database
    }

    /// Inserts the conversation, or updates it when it exists. Children are left alone.
    public func save(_ conversation: Conversation) throws {
        try database.queue.write { db in try conversation.save(db) }
    }

    public func conversation(id: UUID) throws -> Conversation? {
        try database.queue.read { db in try Conversation.fetchOne(db, key: id.uuidString) }
    }

    /// Conversations in one of the given states, oldest first (the order in which to work through them).
    public func conversations(inStates states: [ConversationState]) throws -> [Conversation] {
        guard !states.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: states.count).joined(separator: ", ")
        return try database.queue.read { db in
            try Conversation.fetchAll(
                db,
                sql: "SELECT * FROM conversation WHERE state IN (\(placeholders)) ORDER BY startedAt, id",
                arguments: StatementArguments(states.map(\.rawValue))
            )
        }
    }

    /// Moves a conversation to a new state and replaces its error message (nil clears it).
    /// Returns the updated conversation, or nil when it does not exist.
    @discardableResult
    public func setState(
        _ state: ConversationState,
        lastError: String?,
        for id: UUID,
        now: Date = Date()
    ) throws -> Conversation? {
        try database.queue.write { db in
            guard var conversation = try Conversation.fetchOne(db, key: id.uuidString) else { return nil }
            conversation.state = state
            conversation.lastError = lastError
            conversation.updatedAt = now
            try conversation.update(db)
            return conversation
        }
    }

    /// The most recent conversations, newest first.
    public func recentConversations(limit: Int) throws -> [ConversationSummary] {
        Array(try listConversations().prefix(limit))
    }

    /// All conversations, newest first.
    public func listConversations() throws -> [ConversationSummary] {
        try database.queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT conversation.*,
                  (SELECT json_group_array(name) FROM
                     (SELECT name FROM participant WHERE conversationId = conversation.id ORDER BY isUser DESC, name)
                  ) AS participantNames,
                  (SELECT COUNT(*) FROM segment
                     JOIN transcriptVersion ON transcriptVersion.id = segment.transcriptVersionId
                    WHERE transcriptVersion.conversationId = conversation.id
                      AND transcriptVersion.isCurrent = 1) AS segmentCount,
                  (SELECT COUNT(*) FROM outcome
                    WHERE conversationId = conversation.id AND status = 'proposed') AS proposedOutcomes,
                  (SELECT COUNT(*) FROM outcome
                    WHERE conversationId = conversation.id AND status = 'approved') AS approvedOutcomes
                FROM conversation
                ORDER BY startedAt DESC, id
                """)
            return try rows.map { row in
                let namesJSON: String = row["participantNames"] ?? "[]"
                let names = (try? JSONDecoder().decode([String].self, from: Data(namesJSON.utf8))) ?? []
                return ConversationSummary(
                    conversation: try Conversation(row: row),
                    participantNames: names,
                    segmentCount: row["segmentCount"],
                    proposedOutcomes: row["proposedOutcomes"],
                    approvedOutcomes: row["approvedOutcomes"]
                )
            }
        }
    }

    public func saveParticipants(_ participants: [Participant]) throws {
        try database.queue.write { db in
            for participant in participants { try participant.save(db) }
        }
    }

    /// The user first, then by name.
    public func participants(conversationId: UUID) throws -> [Participant] {
        try database.queue.read { db in
            try Participant.fetchAll(
                db,
                sql: "SELECT * FROM participant WHERE conversationId = ? ORDER BY isUser DESC, name",
                arguments: [conversationId.uuidString]
            )
        }
    }

    public func saveTracks(_ tracks: [Track]) throws {
        try database.queue.write { db in
            for track in tracks { try track.save(db) }
        }
    }

    public func tracks(conversationId: UUID) throws -> [Track] {
        try database.queue.read { db in
            try Track.fetchAll(
                db,
                sql: "SELECT * FROM track WHERE conversationId = ? ORDER BY kind",
                arguments: [conversationId.uuidString]
            )
        }
    }

    /// Stores a transcription pass and makes it the current one. Earlier versions are kept.
    public func saveTranscript(version: TranscriptVersion, segments: [Segment]) throws {
        try database.queue.write { db in
            try Self.insertTranscript(db, version: version, segments: segments)
        }
    }

    static func insertTranscript(_ db: Database, version: TranscriptVersion, segments: [Segment]) throws {
        try db.execute(
            sql: "UPDATE transcriptVersion SET isCurrent = 0 WHERE conversationId = ?",
            arguments: [version.conversationId.uuidString]
        )
        var current = version
        current.isCurrent = true
        try current.insert(db)
        for segment in segments { try segment.insert(db) }
    }

    public func currentTranscriptVersion(conversationId: UUID) throws -> TranscriptVersion? {
        try database.queue.read { db in
            try TranscriptVersion.fetchOne(
                db,
                sql: "SELECT * FROM transcriptVersion WHERE conversationId = ? AND isCurrent = 1",
                arguments: [conversationId.uuidString]
            )
        }
    }

    /// Segments of the current transcript version, in time order.
    public func currentSegments(conversationId: UUID) throws -> [Segment] {
        try database.queue.read { db in
            try Segment.fetchAll(db, sql: """
                SELECT segment.* FROM segment
                  JOIN transcriptVersion ON transcriptVersion.id = segment.transcriptVersionId
                 WHERE transcriptVersion.conversationId = ? AND transcriptVersion.isCurrent = 1
                 ORDER BY segment.startMs, segment.endMs
                """, arguments: [conversationId.uuidString])
        }
    }

    /// Removes the conversation and everything that belongs to it from the database.
    /// Audio files on disk are not touched.
    public func delete(conversationId: UUID) throws {
        try database.queue.write { db in
            try db.execute(sql: "DELETE FROM conversation WHERE id = ?", arguments: [conversationId.uuidString])
        }
    }
}
