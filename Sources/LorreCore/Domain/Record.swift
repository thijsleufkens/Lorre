import Foundation

public enum RecordStatus: String, Codable, CaseIterable, Sendable {
    case draft, approved
}

/// One exported version of a conversation's record.
public struct RecordExport: Codable, Equatable, Sendable {
    public var conversationId: UUID
    public var version: Int
    public var status: RecordStatus
    public var approvedAt: Date?
    public var path: String

    public init(conversationId: UUID, version: Int, status: RecordStatus, approvedAt: Date? = nil, path: String) {
        self.conversationId = conversationId
        self.version = version
        self.status = status
        self.approvedAt = approvedAt
        self.path = path
    }
}

/// What one consumer (an agent, a script) has already picked up.
public struct ConsumerCursor: Codable, Equatable, Sendable {
    public var consumerName: String
    public var conversationId: UUID
    public var recordVersion: Int
    public var processedAt: Date

    public init(consumerName: String, conversationId: UUID, recordVersion: Int, processedAt: Date = Date()) {
        self.consumerName = consumerName
        self.conversationId = conversationId
        self.recordVersion = recordVersion
        self.processedAt = processedAt
    }
}
