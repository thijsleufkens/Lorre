import Foundation

/// What a proposer gets to see: the conversation as Lorre stores it, nothing engine-specific.
public struct ProposalInput: Sendable {
    public var type: ConversationType
    public var language: LorreLanguage
    public var participants: [Participant]
    /// The current transcript, in time order.
    public var segments: [Segment]

    public init(
        type: ConversationType,
        language: LorreLanguage,
        participants: [Participant],
        segments: [Segment]
    ) {
        self.type = type
        self.language = language
        self.participants = participants
        self.segments = segments
    }
}

/// One suggested outcome. It only ever refers to segments that exist in the input.
public struct ProposedOutcome: Equatable, Sendable, Codable {
    public var kind: OutcomeKind
    public var text: String
    public var ownerParticipantId: UUID?
    public var evidenceSegmentIds: [UUID]

    public init(kind: OutcomeKind, text: String, ownerParticipantId: UUID? = nil, evidenceSegmentIds: [UUID] = []) {
        self.kind = kind
        self.text = text
        self.ownerParticipantId = ownerParticipantId
        self.evidenceSegmentIds = evidenceSegmentIds
    }
}

/// Turns a transcript into suggested outcomes. The reviewer approves or rejects them.
/// The app must work without one; nothing outside an adapter knows which model runs.
public protocol OutcomeProposer: Sendable {
    /// Stored with each proposal, e.g. "two-step/ollama:gemma4:e4b".
    var identifier: String { get }
    func propose(_ input: ProposalInput) async throws -> [ProposedOutcome]
}

/// The one thing a language model has to do for Lorre: text in, text out.
public protocol TextGenerator: Sendable {
    var identifier: String { get }
    /// `json` asks the model to answer with JSON only (when the runtime supports it).
    func generate(system: String, prompt: String, json: Bool) async throws -> String
}
