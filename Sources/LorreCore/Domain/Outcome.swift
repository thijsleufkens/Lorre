import Foundation

public enum OutcomeKind: String, Codable, CaseIterable, Sendable {
    case decision, myAction, theirCommitment, openPoint, information, followUpHook, personNote
}

public enum OutcomeStatus: String, Codable, CaseIterable, Sendable {
    case proposed, approved, rejected
}

public enum OutcomeSource: String, Codable, CaseIterable, Sendable {
    case model, user, agent
}

/// Something a conversation produced. Proposed by a model or added by the user; only approved
/// outcomes ever leave Lorre.
public struct Outcome: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var conversationId: UUID
    public var kind: OutcomeKind
    public var text: String
    public var ownerParticipantId: UUID?
    public var due: Date?
    public var status: OutcomeStatus
    /// True when the reviewer changed the proposal before approving it.
    public var edited: Bool
    public var source: OutcomeSource
    public var evidenceSegmentIds: [UUID]
    public var evidenceStartMs: Int?
    public var evidenceEndMs: Int?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        conversationId: UUID,
        kind: OutcomeKind,
        text: String,
        ownerParticipantId: UUID? = nil,
        due: Date? = nil,
        status: OutcomeStatus = .proposed,
        edited: Bool = false,
        source: OutcomeSource,
        evidenceSegmentIds: [UUID] = [],
        evidenceStartMs: Int? = nil,
        evidenceEndMs: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.kind = kind
        self.text = text
        self.ownerParticipantId = ownerParticipantId
        self.due = due
        self.status = status
        self.edited = edited
        self.source = source
        self.evidenceSegmentIds = evidenceSegmentIds
        self.evidenceStartMs = evidenceStartMs
        self.evidenceEndMs = evidenceEndMs
        self.createdAt = createdAt
    }
}
