import Foundation
import GRDB

/// Turns a transcript in the pre-rebuild JSON shape (`transcript.json`) into a transcript version
/// with segments and participants. Used by the legacy import and, until per-track processing
/// replaces it, by the bridge that runs the existing speech pipeline.
enum LegacyTranscriptMapper {
    struct Transcript: Decodable {
        struct Speaker: Decodable {
            var id: String
            var displayName: String?
        }

        struct Segment: Decodable {
            var id: UUID?
            var startMs: Int
            var endMs: Int
            var text: String
            var speakerId: String?
            var confidence: Double?
            var isEdited: Bool?
        }

        var languageHint: String?
        var sourceEngine: String?
        var segments: [Segment]?
        var speakers: [Speaker]?
        var createdAt: Date?
    }

    static func decode(_ data: Data) throws -> Transcript {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Transcript.self, from: data)
    }

    /// Inserts the transcript as the conversation's current version. Speakers become participants,
    /// matched on their engine label so that processing a conversation again does not duplicate them.
    /// Returns the number of segments, or 0 when the transcript is empty (nothing is inserted then).
    @discardableResult
    static func insert(
        _ transcript: Transcript,
        conversationId: UUID,
        defaultDate: Date,
        into db: Database
    ) throws -> Int {
        let segments = transcript.segments ?? []
        guard !segments.isEmpty else { return 0 }

        var participantByLabel: [String: UUID] = [:]
        let existing = try Participant.fetchAll(
            db,
            sql: "SELECT * FROM participant WHERE conversationId = ?",
            arguments: [conversationId.uuidString]
        )
        for participant in existing {
            if let label = participant.sourceLabel { participantByLabel[label] = participant.id }
        }
        func participant(for label: String, name: String?) throws -> UUID {
            if let existing = participantByLabel[label] { return existing }
            let participant = Participant(conversationId: conversationId, name: name ?? label, sourceLabel: label)
            try participant.insert(db)
            participantByLabel[label] = participant.id
            return participant.id
        }
        for speaker in transcript.speakers ?? [] {
            _ = try participant(for: speaker.id, name: speaker.displayName)
        }

        let version = TranscriptVersion(
            conversationId: conversationId,
            engine: transcript.sourceEngine ?? "unknown",
            languageHint: transcript.languageHint,
            createdAt: transcript.createdAt ?? defaultDate
        )
        var seenSegmentIds = Set<UUID>()
        let newSegments = try segments.map { legacy -> Segment in
            // Segment ids must be unique across the database; a duplicated id gets a fresh one.
            var id = legacy.id ?? UUID()
            let isTaken = try seenSegmentIds.contains(id) || Segment.exists(db, key: id.uuidString)
            if isTaken { id = UUID() }
            seenSegmentIds.insert(id)
            return Segment(
                id: id,
                transcriptVersionId: version.id,
                participantId: try legacy.speakerId.map { try participant(for: $0, name: nil) },
                startMs: legacy.startMs,
                endMs: legacy.endMs,
                text: legacy.text,
                confidence: legacy.confidence,
                isEdited: legacy.isEdited ?? false
            )
        }
        try ConversationStore.insertTranscript(db, version: version, segments: newSegments)
        return newSegments.count
    }
}

extension ConversationStore {
    /// Stores a transcript given in the pre-rebuild JSON shape as the conversation's current version.
    /// Returns the number of segments stored.
    @discardableResult
    public func saveTranscript(legacyJSON data: Data, conversationId: UUID, now: Date = Date()) throws -> Int {
        let transcript = try LegacyTranscriptMapper.decode(data)
        return try database.queue.write { db in
            try LegacyTranscriptMapper.insert(transcript, conversationId: conversationId, defaultDate: now, into: db)
        }
    }
}
