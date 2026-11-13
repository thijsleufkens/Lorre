import Foundation

/// Someone the user talks to, across conversations.
public struct Person: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var organisation: String?
    public var role: String?
    public var notes: String?

    public init(id: UUID = UUID(), name: String, organisation: String? = nil, role: String? = nil, notes: String? = nil) {
        self.id = id
        self.name = name
        self.organisation = organisation
        self.role = role
        self.notes = notes
    }
}

/// A speaker in one conversation, optionally linked to a `Person`.
public struct Participant: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var conversationId: UUID
    public var personId: UUID?
    public var name: String
    public var isUser: Bool
    /// The speaker label the engine produced ("S1", "UNK"); kept so re-processing can re-map.
    public var sourceLabel: String?

    public init(
        id: UUID = UUID(),
        conversationId: UUID,
        personId: UUID? = nil,
        name: String,
        isUser: Bool = false,
        sourceLabel: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.personId = personId
        self.name = name
        self.isUser = isUser
        self.sourceLabel = sourceLabel
    }
}
