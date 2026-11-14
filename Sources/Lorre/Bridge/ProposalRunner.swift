import Foundation
import LorreCore

/// Proposes outcomes for a transcribed conversation with the model chosen in the settings.
///
/// Best effort by design: the conversation is reviewable without proposals, so a missing or
/// failing model never fails the processing.
struct ProposalRunner: Sendable {
    let database: LorreDatabase
    /// Builds the proposer for a model name; replaced in tests.
    var makeProposer: @Sendable (String) -> any OutcomeProposer = { model in
        TwoStepOutcomeProposer(generator: OllamaTextGenerator(model: model))
    }

    /// Returns the number of stored proposals; nil when no model is set or the proposal failed.
    @discardableResult
    func run(_ conversationId: UUID, language: LorreLanguage = .current) async -> Int? {
        do {
            let model = try SettingsStore(database: database).string(.proposalModel)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !model.isEmpty else { return nil }
            let store = ConversationStore(database: database)
            guard let conversation = try store.conversation(id: conversationId) else { return nil }
            let segments = try store.currentSegments(conversationId: conversationId)
            guard !segments.isEmpty else { return nil }
            let proposer = makeProposer(model)
            let proposals = try await proposer.propose(ProposalInput(
                type: conversation.type,
                language: language,
                participants: try store.activeParticipants(conversationId: conversationId),
                segments: segments
            ))
            return try ReviewStore(database: database).replaceProposals(
                conversationId: conversationId, proposals: proposals, modelIdentifier: proposer.identifier
            ).count
        } catch {
            return nil
        }
    }
}
