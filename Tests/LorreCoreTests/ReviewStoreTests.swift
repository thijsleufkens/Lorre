import XCTest
@testable import LorreCore

final class ReviewStoreTests: XCTestCase {
    private var database: LorreDatabase!
    private var store: ConversationStore!
    private var review: ReviewStore!
    private var conversation: Conversation!
    private var thijs: Participant!
    private var anna: Participant!
    private var segments: [Segment] = []

    override func setUpWithError() throws {
        database = try LorreDatabase.inMemory()
        store = ConversationStore(database: database)
        review = ReviewStore(database: database)
        conversation = makeConversation(title: "Call")
        try store.save(conversation)
        thijs = Participant(conversationId: conversation.id, name: "Speaker S1", sourceLabel: "S1")
        anna = Participant(conversationId: conversation.id, name: "Speaker S2", sourceLabel: "S2")
        try store.saveParticipants([thijs, anna])
        let version = TranscriptVersion(conversationId: conversation.id, engine: "test")
        segments = [
            Segment(transcriptVersionId: version.id, participantId: thijs.id, startMs: 1_000, endMs: 4_000, text: "Ik stuur morgen de offerte."),
            Segment(transcriptVersionId: version.id, participantId: anna.id, startMs: 5_000, endMs: 9_000, text: "Dan geef ik je naam door aan Jimmy."),
            Segment(transcriptVersionId: version.id, participantId: anna.id, startMs: 10_000, endMs: 12_000, text: "We bellen dinsdag."),
        ]
        try store.saveTranscript(version: version, segments: segments)
    }

    private func state() throws -> ConversationState? {
        try store.conversation(id: conversation.id)?.state
    }

    func testAddedOutcomeIsApprovedAndCarriesItsEvidence() throws {
        let outcome = try review.addOutcome(
            conversationId: conversation.id, kind: .theirCommitment, text: "  Geeft mijn naam door aan Jimmy ",
            ownerParticipantId: anna.id, evidence: [segments[1], segments[2]]
        )
        XCTAssertEqual(outcome.status, .approved)
        XCTAssertEqual(outcome.source, .user)
        XCTAssertEqual(outcome.text, "Geeft mijn naam door aan Jimmy")
        XCTAssertEqual(outcome.evidenceSegmentIds, [segments[1].id, segments[2].id])
        XCTAssertEqual(outcome.evidenceStartMs, 5_000)
        XCTAssertEqual(outcome.evidenceEndMs, 12_000)
        XCTAssertEqual(try review.outcomes(conversationId: conversation.id), [outcome])
    }

    func testOutcomesWithoutOwnerKindDropTheOwner() throws {
        let outcome = try review.addOutcome(
            conversationId: conversation.id, kind: .decision, text: "Niet naar het event", ownerParticipantId: anna.id
        )
        XCTAssertNil(outcome.ownerParticipantId)
    }

    func testOutcomesAreOrderedByWhenTheyCameUp() throws {
        let late = try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "laat", evidence: [segments[2]])
        let none = try review.addOutcome(conversationId: conversation.id, kind: .information, text: "zonder bewijs")
        let early = try review.addOutcome(conversationId: conversation.id, kind: .myAction, text: "vroeg", evidence: [segments[0]])
        XCTAssertEqual(try review.outcomes(conversationId: conversation.id).map(\.id), [early.id, late.id, none.id])
    }

    func testEditingAProposalFlagsItAsEdited() throws {
        let proposed = try review.addOutcome(
            conversationId: conversation.id, kind: .myAction, text: "Stuurt offerte", source: .model
        )
        XCTAssertEqual(proposed.status, .proposed)
        let edited = try review.updateOutcome(proposed.id, text: "Offerte sturen vóór vrijdag", owner: .some(thijs.id))
        XCTAssertTrue(edited.edited)
        XCTAssertEqual(edited.ownerParticipantId, thijs.id)

        let own = try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "x")
        XCTAssertFalse(try review.updateOutcome(own.id, text: "y").edited, "the reviewer's own items are not 'edited'")
    }

    func testChangingKindToOneWithoutOwnerClearsTheOwner() throws {
        let outcome = try review.addOutcome(
            conversationId: conversation.id, kind: .myAction, text: "x", ownerParticipantId: thijs.id
        )
        XCTAssertNil(try review.updateOutcome(outcome.id, kind: .information).ownerParticipantId)
    }

    func testRejectAndDelete() throws {
        let outcome = try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "x", source: .model)
        XCTAssertEqual(try review.setStatus(.rejected, for: outcome.id).status, .rejected)
        XCTAssertEqual(try review.outcomes(conversationId: conversation.id, includingRejected: false), [])
        try review.deleteOutcome(outcome.id)
        XCTAssertEqual(try review.outcomes(conversationId: conversation.id), [])
        XCTAssertThrowsError(try review.setStatus(.approved, for: outcome.id))
    }

    func testFinishApprovesProposalsButNotRejectedOnes() throws {
        let proposed = try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "a", source: .model)
        let rejected = try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "b", source: .model)
        try review.setStatus(.rejected, for: rejected.id)

        let finished = try review.finishReview(conversation.id)

        XCTAssertEqual(finished.state, .approved)
        let statuses = Dictionary(uniqueKeysWithValues: try review.outcomes(conversationId: conversation.id).map { ($0.id, $0.status) })
        XCTAssertEqual(statuses[proposed.id], .approved)
        XCTAssertEqual(statuses[rejected.id], .rejected)
    }

    func testAnyChangeAfterApprovalMarksTheConversationChanged() throws {
        try review.finishReview(conversation.id)
        XCTAssertEqual(try state(), .approved)
        try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "nog iets")
        XCTAssertEqual(try state(), .changed)

        try review.finishReview(conversation.id)
        try review.renameParticipant(anna.id, to: "Anna")
        XCTAssertEqual(try state(), .changed)

        try review.finishReview(conversation.id)
        try review.updateConversation(conversation.id, title: "Call met Anna", type: .network)
        XCTAssertEqual(try state(), .changed)
        XCTAssertEqual(try store.conversation(id: conversation.id)?.type, .network)
    }

    func testNoOpEditsDoNotMarkChanged() throws {
        try review.finishReview(conversation.id)
        try review.updateConversation(conversation.id, title: "Call")
        try review.renameParticipant(anna.id, to: "Speaker S2")
        try review.updateConversation(conversation.id, title: "   ")
        XCTAssertEqual(try state(), .approved)
        XCTAssertEqual(try store.conversation(id: conversation.id)?.title, "Call")
    }

    func testSetUserKeepsExactlyOne() throws {
        try review.setUser(thijs.id, in: conversation.id)
        try review.setUser(anna.id, in: conversation.id)
        let users = try store.participants(conversationId: conversation.id).filter(\.isUser)
        XCTAssertEqual(users.map(\.id), [anna.id])
        try review.setUser(nil, in: conversation.id)
        XCTAssertEqual(try store.participants(conversationId: conversation.id).filter(\.isUser), [])
    }

    func testMergeMovesSegmentsAndOwnership() throws {
        let extra = Participant(conversationId: conversation.id, name: "Speaker S3", isUser: true, sourceLabel: "S3")
        try store.saveParticipants([extra])
        try review.assignSegment(segments[2].id, to: extra.id)
        let owned = try review.addOutcome(
            conversationId: conversation.id, kind: .theirCommitment, text: "x", ownerParticipantId: extra.id
        )

        try review.mergeParticipant(extra.id, into: anna.id)

        let participants = try store.participants(conversationId: conversation.id)
        XCTAssertEqual(Set(participants.map(\.id)), [thijs.id, anna.id])
        XCTAssertEqual(participants.first { $0.id == anna.id }?.isUser, true, "being the user travels with the merge")
        XCTAssertEqual(try store.currentSegments(conversationId: conversation.id).map(\.participantId), [thijs.id, anna.id, anna.id])
        XCTAssertEqual(try review.outcomes(conversationId: conversation.id).first { $0.id == owned.id }?.ownerParticipantId, anna.id)
        XCTAssertThrowsError(try review.mergeParticipant(anna.id, into: anna.id))
    }

    func testMergeAcrossConversationsIsRefused() throws {
        let other = makeConversation(title: "Other")
        try store.save(other)
        let stranger = Participant(conversationId: other.id, name: "X")
        try store.saveParticipants([stranger])
        XCTAssertThrowsError(try review.mergeParticipant(stranger.id, into: anna.id))
        XCTAssertEqual(try store.participants(conversationId: other.id).count, 1)
    }

    func testToReviewLeavesOutImportedAndApproved() throws {
        var imported = makeConversation(title: "Imported")
        imported.importedAt = Date()
        try store.save(imported)
        var recording = makeConversation(title: "Recording")
        recording.state = .recording
        try store.save(recording)

        XCTAssertEqual(try review.conversationsToReview().map(\.conversation.title), ["Call"])
        try review.finishReview(conversation.id)
        XCTAssertEqual(try review.conversationsToReview().count, 0)
        try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "x")
        XCTAssertEqual(try review.conversationsToReview().map(\.conversation.title), ["Call"], "a changed one waits again")
    }

    func testSettingsRoundTripAndDefaults() throws {
        let settings = SettingsStore(database: database)
        XCTAssertEqual(try settings.exportFolder(), SettingsStore.defaultExportFolder())
        try settings.set("/tmp/records", for: .exportFolder)
        XCTAssertEqual(try settings.exportFolder().path, "/tmp/records")
        try settings.set("Thijs", for: .userName)
        XCTAssertEqual(try settings.userName(), "Thijs")
        try settings.set(nil, for: .exportFolder)
        XCTAssertEqual(try settings.exportFolder(), SettingsStore.defaultExportFolder())
    }

    func testLanguagePreference() {
        XCTAssertEqual(LorreLanguage.preferred(from: ["nl-NL", "en-US"]), .dutch)
        XCTAssertEqual(LorreLanguage.preferred(from: ["en-GB", "nl-NL"]), .english)
        XCTAssertEqual(LorreLanguage.preferred(from: ["de-DE", "nl"]), .dutch)
        XCTAssertEqual(LorreLanguage.preferred(from: ["fr-FR"]), .english)
        XCTAssertEqual(Set(OutcomeKind.displayOrder), Set(OutcomeKind.allCases))
    }
}
