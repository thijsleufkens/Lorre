import Foundation

extension ConversationStore {
    /// The participants that matter for the current transcript: everyone who speaks in it, plus
    /// the user. Labels left over from an earlier transcript version are left out.
    public func activeParticipants(conversationId: UUID) throws -> [Participant] {
        let speaking = Set(try currentSegments(conversationId: conversationId).compactMap(\.participantId))
        let all = try participants(conversationId: conversationId)
        guard !speaking.isEmpty else { return all }
        return all.filter { $0.isUser || speaking.contains($0.id) }
    }
}
