import Foundation
import GRDB

/// Everything a reviewer can do to a conversation: add and judge outcomes, fix who is who,
/// correct the title and type, and finish.
///
/// Any change to a conversation that was already approved marks it `changed`, so it is clear
/// that the exported record no longer matches.
public struct ReviewStore: Sendable {
    public enum ReviewError: Error, Equatable {
        case conversationNotFound
        case outcomeNotFound
        case participantNotFound
        case cannotMergeParticipantWithItself
    }

    let database: LorreDatabase

    public init(database: LorreDatabase) {
        self.database = database
    }

    // MARK: Outcomes

    /// Outcomes of a conversation in the order they came up; those without evidence last.
    public func outcomes(conversationId: UUID, includingRejected: Bool = true) throws -> [Outcome] {
        try database.queue.read { db in
            try Outcome.fetchAll(db, sql: """
                SELECT * FROM outcome
                 WHERE conversationId = ? \(includingRejected ? "" : "AND status != 'rejected'")
                 ORDER BY evidenceStartMs IS NULL, evidenceStartMs, createdAt, id
                """, arguments: [conversationId.uuidString])
        }
    }

    /// Adds an outcome written by the reviewer. It is approved right away: the reviewer is the judge.
    @discardableResult
    public func addOutcome(
        conversationId: UUID,
        kind: OutcomeKind,
        text: String,
        ownerParticipantId: UUID? = nil,
        due: Date? = nil,
        evidence segments: [Segment] = [],
        source: OutcomeSource = .user,
        now: Date = Date()
    ) throws -> Outcome {
        let outcome = Outcome(
            conversationId: conversationId,
            kind: kind,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            ownerParticipantId: kind.hasOwner ? ownerParticipantId : nil,
            due: due,
            status: source == .user ? .approved : .proposed,
            edited: false,
            source: source,
            evidenceSegmentIds: segments.map(\.id),
            evidenceStartMs: segments.map(\.startMs).min(),
            evidenceEndMs: segments.map(\.endMs).max(),
            createdAt: now
        )
        return try database.queue.write { db in
            guard try Conversation.exists(db, key: conversationId.uuidString) else {
                throw ReviewError.conversationNotFound
            }
            try outcome.insert(db)
            try Self.markChanged(db, conversationId: conversationId, now: now)
            // Return what is stored: the database keeps dates to the millisecond.
            return try Outcome.fetchOne(db, key: outcome.id.uuidString) ?? outcome
        }
    }

    /// Changes text, kind, owner or due date. A proposal that the reviewer rewrites is flagged as edited.
    @discardableResult
    public func updateOutcome(
        _ id: UUID,
        text: String? = nil,
        kind: OutcomeKind? = nil,
        owner: UUID?? = nil,
        due: Date?? = nil,
        now: Date = Date()
    ) throws -> Outcome {
        try database.queue.write { db in
            guard var outcome = try Outcome.fetchOne(db, key: id.uuidString) else {
                throw ReviewError.outcomeNotFound
            }
            let before = outcome
            if let text { outcome.text = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let kind { outcome.kind = kind }
            if let owner { outcome.ownerParticipantId = owner }
            if let due { outcome.due = due }
            if !outcome.kind.hasOwner { outcome.ownerParticipantId = nil }
            guard outcome != before else { return outcome }
            if outcome.source != .user { outcome.edited = true }
            try outcome.update(db)
            try Self.markChanged(db, conversationId: outcome.conversationId, now: now)
            return outcome
        }
    }

    @discardableResult
    public func setStatus(_ status: OutcomeStatus, for id: UUID, now: Date = Date()) throws -> Outcome {
        try database.queue.write { db in
            guard var outcome = try Outcome.fetchOne(db, key: id.uuidString) else {
                throw ReviewError.outcomeNotFound
            }
            guard outcome.status != status else { return outcome }
            outcome.status = status
            try outcome.update(db)
            try Self.markChanged(db, conversationId: outcome.conversationId, now: now)
            return outcome
        }
    }

    /// Replaces the model's untouched proposals with a new set, in one transaction.
    ///
    /// Deleted: outcomes that came from a model, are still `proposed` and were not edited.
    /// Approved, rejected, edited and user-added outcomes are never touched. Evidence segments that
    /// are not in the conversation's current transcript are dropped; an owner who is not a participant
    /// becomes nil. `modelIdentifier` is accepted for the caller's bookkeeping but `Outcome` has no
    /// field for it yet, so it is not stored.
    @discardableResult
    public func replaceProposals(
        conversationId: UUID,
        proposals: [ProposedOutcome],
        modelIdentifier: String,
        now: Date = Date()
    ) throws -> [Outcome] {
        _ = modelIdentifier
        return try database.queue.write { db in
            guard try Conversation.exists(db, key: conversationId.uuidString) else {
                throw ReviewError.conversationNotFound
            }
            let segments = try Segment.fetchAll(db, sql: """
                SELECT segment.* FROM segment
                  JOIN transcriptVersion ON transcriptVersion.id = segment.transcriptVersionId
                 WHERE transcriptVersion.conversationId = ? AND transcriptVersion.isCurrent = 1
                """, arguments: [conversationId.uuidString])
            let segmentsById = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
            let participantIds = Set(try Participant.fetchAll(
                db, sql: "SELECT * FROM participant WHERE conversationId = ?", arguments: [conversationId.uuidString]
            ).map(\.id))

            try db.execute(
                sql: "DELETE FROM outcome WHERE conversationId = ? AND source = 'model' AND status = 'proposed' AND edited = 0",
                arguments: [conversationId.uuidString]
            )
            let deleted = db.changesCount

            var inserted: [Outcome] = []
            for proposal in proposals {
                let text = proposal.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let evidence = proposal.evidenceSegmentIds.compactMap { segmentsById[$0] }
                let owner = proposal.ownerParticipantId.flatMap { participantIds.contains($0) ? $0 : nil }
                let outcome = Outcome(
                    conversationId: conversationId,
                    kind: proposal.kind,
                    text: text,
                    ownerParticipantId: proposal.kind.hasOwner ? owner : nil,
                    status: .proposed,
                    edited: false,
                    source: .model,
                    evidenceSegmentIds: evidence.map(\.id),
                    evidenceStartMs: evidence.map(\.startMs).min(),
                    evidenceEndMs: evidence.map(\.endMs).max(),
                    createdAt: now
                )
                try outcome.insert(db)
                inserted.append(try Outcome.fetchOne(db, key: outcome.id.uuidString) ?? outcome)
            }
            if deleted > 0 || !inserted.isEmpty {
                try Self.markChanged(db, conversationId: conversationId, now: now)
            }
            return inserted
        }
    }

    /// Removes an outcome the reviewer added by mistake.
    public func deleteOutcome(_ id: UUID, now: Date = Date()) throws {
        try database.queue.write { db in
            guard let outcome = try Outcome.fetchOne(db, key: id.uuidString) else { return }
            try outcome.delete(db)
            try Self.markChanged(db, conversationId: outcome.conversationId, now: now)
        }
    }

    // MARK: Conversation and people

    public func updateConversation(
        _ id: UUID,
        title: String? = nil,
        type: ConversationType? = nil,
        now: Date = Date()
    ) throws {
        try database.queue.write { db in
            guard var conversation = try Conversation.fetchOne(db, key: id.uuidString) else {
                throw ReviewError.conversationNotFound
            }
            let before = conversation
            if let title {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { conversation.title = trimmed }
            }
            if let type { conversation.type = type }
            guard conversation != before else { return }
            if conversation.state == .approved { conversation.state = .changed }
            conversation.updatedAt = now
            try conversation.update(db)
        }
    }

    public func renameParticipant(_ id: UUID, to name: String, now: Date = Date()) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try database.queue.write { db in
            guard var participant = try Participant.fetchOne(db, key: id.uuidString) else {
                throw ReviewError.participantNotFound
            }
            guard participant.name != trimmed else { return }
            participant.name = trimmed
            try participant.update(db)
            try Self.markChanged(db, conversationId: participant.conversationId, now: now)
        }
    }

    /// Marks one participant as the user (or nobody, with nil). There is at most one per conversation.
    public func setUser(_ participantId: UUID?, in conversationId: UUID, now: Date = Date()) throws {
        try database.queue.write { db in
            try db.execute(
                sql: "UPDATE participant SET isUser = (id = ?) WHERE conversationId = ?",
                arguments: [participantId?.uuidString ?? "", conversationId.uuidString]
            )
            try Self.markChanged(db, conversationId: conversationId, now: now)
        }
    }

    /// "These two are the same person": everything said by and owned by `source` moves to `target`.
    public func mergeParticipant(_ source: UUID, into target: UUID, now: Date = Date()) throws {
        guard source != target else { throw ReviewError.cannotMergeParticipantWithItself }
        try database.queue.write { db in
            guard let from = try Participant.fetchOne(db, key: source.uuidString),
                  var into = try Participant.fetchOne(db, key: target.uuidString),
                  from.conversationId == into.conversationId else {
                throw ReviewError.participantNotFound
            }
            try db.execute(
                sql: "UPDATE segment SET participantId = ? WHERE participantId = ?",
                arguments: [target.uuidString, source.uuidString]
            )
            try db.execute(
                sql: "UPDATE outcome SET ownerParticipantId = ? WHERE ownerParticipantId = ?",
                arguments: [target.uuidString, source.uuidString]
            )
            if from.isUser && !into.isUser {
                into.isUser = true
                try into.update(db)
            }
            if into.personId == nil, let personId = from.personId {
                into.personId = personId
                try into.update(db)
            }
            try from.delete(db)
            try Self.markChanged(db, conversationId: into.conversationId, now: now)
        }
    }

    /// Changes who said one segment.
    public func assignSegment(_ segmentId: UUID, to participantId: UUID?, now: Date = Date()) throws {
        try database.queue.write { db in
            try db.execute(
                sql: "UPDATE segment SET participantId = ?, isEdited = 1 WHERE id = ?",
                arguments: [participantId?.uuidString, segmentId.uuidString]
            )
            if let conversationId = try String.fetchOne(db, sql: """
                SELECT transcriptVersion.conversationId FROM segment
                  JOIN transcriptVersion ON transcriptVersion.id = segment.transcriptVersionId
                 WHERE segment.id = ?
                """, arguments: [segmentId.uuidString]).flatMap(UUID.init(uuidString:)) {
                try Self.markChanged(db, conversationId: conversationId, now: now)
            }
        }
    }

    // MARK: Finishing

    /// Approves everything that is still proposed and marks the conversation approved.
    /// Returns the conversation in its new state.
    @discardableResult
    public func finishReview(_ conversationId: UUID, now: Date = Date()) throws -> Conversation {
        try database.queue.write { db in
            guard var conversation = try Conversation.fetchOne(db, key: conversationId.uuidString) else {
                throw ReviewError.conversationNotFound
            }
            try db.execute(
                sql: "UPDATE outcome SET status = 'approved' WHERE conversationId = ? AND status = 'proposed'",
                arguments: [conversationId.uuidString]
            )
            conversation.state = .approved
            conversation.updatedAt = now
            try conversation.update(db)
            return conversation
        }
    }

    /// Conversations that wait for the reviewer: transcribed, not yet approved. Imported ones are
    /// left out; they were never waiting for anything.
    public func conversationsToReview() throws -> [ConversationSummary] {
        try ConversationStore(database: database).listConversations().filter { summary in
            let conversation = summary.conversation
            return (conversation.state == .proposed || conversation.state == .changed)
                && conversation.importedAt == nil
        }
    }

    private static func markChanged(_ db: Database, conversationId: UUID, now: Date) throws {
        try db.execute(
            sql: """
                UPDATE conversation
                   SET state = CASE WHEN state = 'approved' THEN 'changed' ELSE state END, updatedAt = ?
                 WHERE id = ?
                """,
            arguments: [now, conversationId.uuidString]
        )
    }
}
