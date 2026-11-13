import Foundation

/// The raw values of the enums in this module are stored in the database and exported in records.
/// They are part of the contract: do not rename a case without a migration.
public enum ConversationType: String, Codable, CaseIterable, Sendable {
    case workMeeting, intake, network, other
}

public enum ConversationState: String, Codable, CaseIterable, Sendable {
    case recording, interrupted, processing, proposed, approved, changed
}

public struct Conversation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var type: ConversationType
    public var state: ConversationState
    public var startedAt: Date
    public var durationSeconds: Double?
    public var calendarEventId: String?
    /// Set when the conversation came from the pre-rebuild file store.
    public var importedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        type: ConversationType = .other,
        state: ConversationState,
        startedAt: Date,
        durationSeconds: Double? = nil,
        calendarEventId: String? = nil,
        importedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.state = state
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.calendarEventId = calendarEventId
        self.importedAt = importedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
