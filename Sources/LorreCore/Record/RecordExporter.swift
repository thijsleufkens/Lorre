import Foundation
import GRDB

/// Writes the record of a conversation to the export folder, as JSON for agents and Markdown for
/// people, and remembers which version went where.
public struct RecordExporter: Sendable {
    public struct Exported: Equatable, Sendable {
        public var record: MeetingRecord
        public var json: URL
        public var markdown: URL
    }

    private let database: LorreDatabase
    private let folder: @Sendable () throws -> URL
    private let language: LorreLanguage
    private let now: @Sendable () -> Date

    /// - Parameter folder: where to write; by default the folder from the settings.
    public init(
        database: LorreDatabase,
        folder: (@Sendable () throws -> URL)? = nil,
        language: LorreLanguage = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.database = database
        self.folder = folder ?? { try SettingsStore(database: database).exportFolder() }
        self.language = language
        self.now = now
    }

    /// The record as it would be exported now, without writing anything.
    public func buildRecord(conversationId: UUID, status: RecordStatus) throws -> MeetingRecord {
        try database.queue.read { db in
            try Self.build(db, conversationId: conversationId, status: status, version: 0, approvedAt: nil)
        }
    }

    /// Writes the transcript-only record of a conversation that has not been reviewed.
    /// Does nothing when an approved record already exists.
    @discardableResult
    public func exportDraft(_ conversationId: UUID) throws -> Exported? {
        let hasApproved = try database.queue.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM recordExport WHERE conversationId = ? AND status = 'approved')
                """, arguments: [conversationId.uuidString]) ?? false
        }
        guard !hasApproved else { return nil }
        return try export(conversationId, status: .draft)
    }

    /// Writes the approved record. Each call after a change produces the next version.
    @discardableResult
    public func exportApproved(_ conversationId: UUID) throws -> Exported {
        try export(conversationId, status: .approved)
    }

    /// The latest export of a conversation, if any.
    public func latestExport(_ conversationId: UUID) throws -> RecordExport? {
        try database.queue.read { db in
            try RecordExport.fetchOne(db, sql: """
                SELECT * FROM recordExport WHERE conversationId = ? ORDER BY version DESC LIMIT 1
                """, arguments: [conversationId.uuidString])
        }
    }

    private func export(_ conversationId: UUID, status: RecordStatus) throws -> Exported {
        let folder = try self.folder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let timestamp = now()

        let (record, previousPath) = try database.queue.read { db -> (MeetingRecord, String?) in
            let lastApproved = try Int.fetchOne(db, sql: """
                SELECT MAX(version) FROM recordExport WHERE conversationId = ? AND status = 'approved'
                """, arguments: [conversationId.uuidString]) ?? 0
            let version = status == .approved ? lastApproved + 1 : 0
            let record = try Self.build(
                db, conversationId: conversationId, status: status, version: version,
                approvedAt: status == .approved ? timestamp : nil
            )
            let previous = try String.fetchOne(db, sql: """
                SELECT path FROM recordExport WHERE conversationId = ? ORDER BY version DESC LIMIT 1
                """, arguments: [conversationId.uuidString])
            return (record, previous)
        }

        let jsonURL = destination(for: record, in: folder, replacing: previousPath)
        let markdownURL = jsonURL.deletingPathExtension().appendingPathExtension("md")

        // A record that was exported under another name (the title changed) is replaced, not duplicated.
        if let previousPath, previousPath != jsonURL.path {
            let old = URL(fileURLWithPath: previousPath)
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.removeItem(at: old.deletingPathExtension().appendingPathExtension("md"))
        }

        try MeetingRecord.encoder().encode(record).write(to: jsonURL, options: .atomic)
        try Data(RecordMarkdown.render(record, language: language).utf8).write(to: markdownURL, options: .atomic)

        try database.queue.write { db in
            try RecordExport(
                conversationId: conversationId,
                version: record.recordVersion,
                status: status,
                approvedAt: record.approvedAt,
                path: jsonURL.path
            ).save(db)
        }
        return Exported(record: record, json: jsonURL, markdown: markdownURL)
    }

    /// `<date> <title>.json`; when another conversation already owns that name, the short id is added.
    private func destination(for record: MeetingRecord, in folder: URL, replacing previousPath: String?) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let base = "\(formatter.string(from: record.conversation.startedAt)) \(Self.safeFileName(record.conversation.title))"
        let plain = folder.appendingPathComponent(base).appendingPathExtension("json")
        if plain.path == previousPath || !FileManager.default.fileExists(atPath: plain.path) { return plain }
        if Self.recordId(at: plain) == record.recordId { return plain }
        let short = record.recordId.uuidString.prefix(8).lowercased()
        return folder.appendingPathComponent("\(base) \(short)").appendingPathExtension("json")
    }

    private static func recordId(at url: URL) -> UUID? {
        struct Probe: Decodable { var recordId: UUID }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(Probe.self, from: data))?.recordId
    }

    static func safeFileName(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = title.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
        let collapsed = cleaned.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let trimmed = String(collapsed.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return trimmed.isEmpty ? "conversation" : trimmed
    }

    private static func build(
        _ db: Database,
        conversationId: UUID,
        status: RecordStatus,
        version: Int,
        approvedAt: Date?
    ) throws -> MeetingRecord {
        guard let conversation = try Conversation.fetchOne(db, key: conversationId.uuidString) else {
            throw ReviewStore.ReviewError.conversationNotFound
        }
        let participants = try Participant.fetchAll(
            db,
            sql: "SELECT * FROM participant WHERE conversationId = ? ORDER BY isUser DESC, name",
            arguments: [conversationId.uuidString]
        )
        let version_ = try TranscriptVersion.fetchOne(
            db,
            sql: "SELECT * FROM transcriptVersion WHERE conversationId = ? AND isCurrent = 1",
            arguments: [conversationId.uuidString]
        )
        let segments = try Segment.fetchAll(db, sql: """
            SELECT segment.* FROM segment
              JOIN transcriptVersion ON transcriptVersion.id = segment.transcriptVersionId
             WHERE transcriptVersion.conversationId = ? AND transcriptVersion.isCurrent = 1
             ORDER BY segment.startMs, segment.endMs
            """, arguments: [conversationId.uuidString])
        // Labels left over from an earlier transcript version do not belong in the record.
        let referenced = Set(segments.compactMap(\.participantId))
        let outcomes: [Outcome] = status == .approved
            ? try Outcome.fetchAll(db, sql: """
                SELECT * FROM outcome WHERE conversationId = ? AND status = 'approved'
                 ORDER BY evidenceStartMs IS NULL, evidenceStartMs, createdAt, id
                """, arguments: [conversationId.uuidString])
            : []

        let outcomeOwners = Set(outcomes.compactMap(\.ownerParticipantId))
        return MeetingRecord(
            schemaVersion: MeetingRecord.currentSchemaVersion,
            recordId: conversation.id,
            recordVersion: version,
            status: status,
            conversation: .init(
                id: conversation.id,
                title: conversation.title,
                type: conversation.type,
                startedAt: conversation.startedAt,
                durationSeconds: conversation.durationSeconds,
                participants: participants.filter {
                    referenced.isEmpty || $0.isUser || referenced.contains($0.id)
                        || outcomeOwners.contains($0.id)
                }.map {
                    .init(id: $0.id, name: $0.name, isUser: $0.isUser, personId: $0.personId)
                }
            ),
            outcomes: outcomes.map {
                .init(
                    id: $0.id, kind: $0.kind, text: $0.text, ownerId: $0.ownerParticipantId, due: $0.due,
                    edited: $0.edited,
                    evidence: .init(
                        segmentIds: $0.evidenceSegmentIds, startMs: $0.evidenceStartMs, endMs: $0.evidenceEndMs
                    )
                )
            },
            transcript: .init(
                engine: version_?.engine,
                segments: segments.map {
                    .init(id: $0.id, participantId: $0.participantId, startMs: $0.startMs, endMs: $0.endMs, text: $0.text)
                }
            ),
            approvedAt: approvedAt
        )
    }
}
