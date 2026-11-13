import Foundation

/// The record of a conversation as it leaves Lorre: the contract with whatever reads it next.
///
/// A draft carries the transcript only. An approved record adds the outcomes the reviewer approved.
/// Nothing that was merely proposed is ever in a record.
public struct MeetingRecord: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public struct ConversationInfo: Codable, Equatable, Sendable {
        public var id: UUID
        public var title: String
        public var type: ConversationType
        public var startedAt: Date
        public var durationSeconds: Double?
        public var participants: [ParticipantInfo]
    }

    public struct ParticipantInfo: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var isUser: Bool
        public var personId: UUID?
    }

    public struct OutcomeInfo: Codable, Equatable, Sendable {
        public struct Evidence: Codable, Equatable, Sendable {
            public var segmentIds: [UUID]
            public var startMs: Int?
            public var endMs: Int?
        }

        public var id: UUID
        public var kind: OutcomeKind
        public var text: String
        public var ownerId: UUID?
        public var due: Date?
        public var edited: Bool
        public var evidence: Evidence
    }

    public struct TranscriptInfo: Codable, Equatable, Sendable {
        public struct SegmentInfo: Codable, Equatable, Sendable {
            public var id: UUID
            public var participantId: UUID?
            public var startMs: Int
            public var endMs: Int
            public var text: String
        }

        public var engine: String?
        public var segments: [SegmentInfo]
    }

    public var schemaVersion: Int
    /// Stable per conversation.
    public var recordId: UUID
    /// 0 for a draft; 1 for the first approval, one more for every re-approval after a change.
    public var recordVersion: Int
    public var status: RecordStatus
    public var conversation: ConversationInfo
    public var outcomes: [OutcomeInfo]
    public var transcript: TranscriptInfo
    public var approvedAt: Date?

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
