import Foundation
import LorreCore
import Observation

/// State behind the review of one conversation: judging proposed outcomes, adding your own,
/// fixing who is who, playing the evidence and finishing.
///
/// Every change goes through `ReviewStore`, after which the model reloads from the database.
@MainActor
@Observable
final class ReviewModel {
    struct Group: Identifiable, Equatable {
        var kind: OutcomeKind
        var items: [Outcome]
        var id: OutcomeKind { kind }
    }

    let conversationID: UUID
    private(set) var conversation: Conversation?
    /// The user first, then by name.
    private(set) var participants: [Participant] = []
    /// The current transcript, in time order.
    private(set) var segments: [Segment] = []
    /// Rejected outcomes are left out.
    private(set) var outcomes: [Outcome] = []
    var selectedOutcomeID: UUID?
    /// The reviewer's selection in the transcript.
    var selectedSegmentIDs: Set<UUID> = []
    private(set) var errorMessage: String?
    private(set) var lastExport: RecordExporter.Exported?
    /// True right after a successful `finish()`; any later edit makes it false again.
    private(set) var isFinished = false

    @ObservationIgnored private let database: LorreDatabase
    @ObservationIgnored private let paths: LorrePaths
    @ObservationIgnored private let player: any EvidencePlaying
    @ObservationIgnored private let exporter: RecordExporter
    @ObservationIgnored private let language: LorreLanguage
    @ObservationIgnored private var audioURL: URL?

    init(
        conversationID: UUID,
        database: LorreDatabase,
        paths: LorrePaths,
        player: any EvidencePlaying,
        exporter: RecordExporter? = nil,
        language: LorreLanguage = .current
    ) {
        self.conversationID = conversationID
        self.database = database
        self.paths = paths
        self.player = player
        self.exporter = exporter ?? RecordExporter(database: database, language: language)
        self.language = language
    }

    private var review: ReviewStore { ReviewStore(database: database) }

    // MARK: Derived state

    var groups: [Group] {
        OutcomeKind.displayOrder.compactMap { kind in
            let items = outcomes.filter { $0.kind == kind }
            return items.isEmpty ? nil : Group(kind: kind, items: items)
        }
    }

    /// Outcomes in the order they are shown.
    private var orderedOutcomes: [Outcome] { groups.flatMap(\.items) }

    var pendingCount: Int { outcomes.filter { $0.status == .proposed }.count }

    var selectedOutcome: Outcome? {
        guard let selectedOutcomeID else { return nil }
        return outcomes.first { $0.id == selectedOutcomeID }
    }

    /// The evidence of the selected outcome plus one segment of context on each side.
    var evidenceSegments: [Segment] {
        guard let outcome = selectedOutcome, !outcome.evidenceSegmentIds.isEmpty else { return [] }
        let ids = Set(outcome.evidenceSegmentIds)
        let indices = segments.indices.filter { ids.contains(segments[$0].id) }
        guard let first = indices.min(), let last = indices.max() else { return [] }
        return Array(segments[max(0, first - 1)...min(segments.count - 1, last + 1)])
    }

    var canPlay: Bool { audioURL != nil }

    var isPlaying: Bool { player.isPlaying }

    func name(of participantID: UUID?) -> String {
        guard let participantID, let participant = participants.first(where: { $0.id == participantID }) else {
            return "?"
        }
        return participant.name
    }

    // MARK: Loading

    func load() {
        do {
            let store = ConversationStore(database: database)
            conversation = try store.conversation(id: conversationID)
            participants = try store.participants(conversationId: conversationID)
            segments = try store.currentSegments(conversationId: conversationID)
            outcomes = try review.outcomes(conversationId: conversationID, includingRejected: false)
            audioURL = AudioLocator.playableURL(tracks: try store.tracks(conversationId: conversationID), paths: paths)
        } catch {
            errorMessage = error.localizedDescription
        }
        if let selectedOutcomeID, !outcomes.contains(where: { $0.id == selectedOutcomeID }) {
            self.selectedOutcomeID = nil
        }
    }

    /// Runs a change, clears or sets the error message, and reloads. Returns whether it worked.
    @discardableResult
    private func perform(editsRecord: Bool = true, _ change: () throws -> Void) -> Bool {
        var succeeded = true
        do {
            try change()
            errorMessage = nil
            if editsRecord { isFinished = false }
        } catch {
            errorMessage = error.localizedDescription
            succeeded = false
        }
        load()
        return succeeded
    }

    private func fail(dutch: String, english: String) {
        errorMessage = language == .dutch ? dutch : english
    }

    // MARK: Selection and judging

    func select(_ outcomeID: UUID?) {
        selectedOutcomeID = outcomeID
    }

    func selectNext() { move(by: 1) }

    func selectPrevious() { move(by: -1) }

    private func move(by step: Int) {
        let ordered = orderedOutcomes
        guard !ordered.isEmpty else { return }
        guard let current = ordered.firstIndex(where: { $0.id == selectedOutcomeID }) else {
            selectedOutcomeID = (step > 0 ? ordered.first : ordered.last)?.id
            return
        }
        let target = current + step
        guard ordered.indices.contains(target) else { return }
        selectedOutcomeID = ordered[target].id
    }

    func approveSelected() {
        guard let id = selectedOutcomeID else { return }
        let changed = perform { try review.setStatus(.approved, for: id) }
        guard changed else { return }
        // Move on to the next outcome that still needs a decision: after this one first, then from the top.
        let ordered = orderedOutcomes
        guard let position = ordered.firstIndex(where: { $0.id == id }) else { return }
        let candidates = ordered[(position + 1)...] + ordered[..<position]
        if let next = candidates.first(where: { $0.status == .proposed }) {
            selectedOutcomeID = next.id
        }
    }

    func rejectSelected() {
        guard let id = selectedOutcomeID else { return }
        let ordered = orderedOutcomes
        let position = ordered.firstIndex { $0.id == id }
        let successor = position.flatMap { index in
            ordered.indices.contains(index + 1) ? ordered[index + 1].id
                : (index > 0 ? ordered[index - 1].id : nil)
        }
        guard perform({ try review.setStatus(.rejected, for: id) }) else { return }
        selectedOutcomeID = successor
    }

    /// Takes the selected outcome off the list: a point you added yourself is deleted,
    /// a proposal is rejected.
    func removeSelected() {
        if selectedOutcome?.source == .user { deleteSelected() } else { rejectSelected() }
    }

    func deleteSelected() {
        guard let outcome = selectedOutcome else { return }
        guard outcome.source == .user else {
            fail(
                dutch: "Alleen punten die je zelf hebt toegevoegd kun je verwijderen. Wijs dit voorstel af.",
                english: "Only outcomes you added yourself can be deleted. Reject this proposal instead."
            )
            return
        }
        let ordered = orderedOutcomes
        let position = ordered.firstIndex { $0.id == outcome.id }
        let successor = position.flatMap { index in
            ordered.indices.contains(index + 1) ? ordered[index + 1].id
                : (index > 0 ? ordered[index - 1].id : nil)
        }
        guard perform({ try review.deleteOutcome(outcome.id) }) else { return }
        selectedOutcomeID = successor
    }

    func updateSelected(text: String? = nil, kind: OutcomeKind? = nil, owner: UUID?? = nil, due: Date?? = nil) {
        guard let id = selectedOutcomeID else { return }
        perform { try review.updateOutcome(id, text: text, kind: kind, owner: owner, due: due) }
    }

    /// Adds an outcome with the current transcript selection as evidence.
    func addOutcome(kind: OutcomeKind, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fail(dutch: "Schrijf eerst wat er is afgesproken.", english: "Write down what was agreed first.")
            return
        }
        let evidence = segments.filter { selectedSegmentIDs.contains($0.id) }
        let user = participants.first(where: \.isUser)
        var owner: UUID?
        switch kind {
        case .myAction:
            owner = user?.id
        case .theirCommitment:
            if let speaker = evidence.first?.participantId, speaker != user?.id { owner = speaker }
        default:
            break
        }
        var added: Outcome?
        guard perform({
            added = try review.addOutcome(
                conversationId: conversationID, kind: kind, text: trimmed, ownerParticipantId: owner, evidence: evidence
            )
        }) else { return }
        selectedSegmentIDs = []
        selectedOutcomeID = added?.id
    }

    // MARK: Conversation and people

    func setTitle(_ title: String) {
        perform { try review.updateConversation(conversationID, title: title) }
    }

    func setType(_ type: ConversationType) {
        perform { try review.updateConversation(conversationID, type: type) }
    }

    func rename(_ participantID: UUID, to name: String) {
        perform { try review.renameParticipant(participantID, to: name) }
    }

    func merge(_ participantID: UUID, into targetID: UUID) {
        perform { try review.mergeParticipant(participantID, into: targetID) }
    }

    func setUser(_ participantID: UUID?) {
        perform { try review.setUser(participantID, in: conversationID) }
    }

    func assign(segmentID: UUID, to participantID: UUID?) {
        perform { try review.assignSegment(segmentID, to: participantID) }
    }

    // MARK: Playback

    /// Plays the range of the selected outcome; does nothing without one.
    func playEvidence() {
        guard let outcome = selectedOutcome, let start = outcome.evidenceStartMs, let audioURL else { return }
        player.play(url: audioURL, startMs: start, endMs: outcome.evidenceEndMs)
    }

    /// Plays from the start of the segment to the end of the recording.
    func play(segmentID: UUID) {
        guard let segment = segments.first(where: { $0.id == segmentID }), let audioURL else { return }
        player.play(url: audioURL, startMs: segment.startMs, endMs: nil)
    }

    func stopPlayback() {
        player.stop()
    }

    // MARK: Finishing

    /// Approves everything still proposed, marks the conversation approved and writes the record.
    /// Returns false and sets `errorMessage` when the export fails; the approval itself is kept.
    @discardableResult
    func finish() -> Bool {
        guard perform(editsRecord: false, { try review.finishReview(conversationID) }) else { return false }
        do {
            lastExport = try exporter.exportApproved(conversationID)
            errorMessage = nil
            isFinished = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            isFinished = false
            return false
        }
    }
}
