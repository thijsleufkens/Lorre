import XCTest
@testable import LorreCore

final class ReplaceProposalsTests: XCTestCase {
    private var database: LorreDatabase!
    private var review: ReviewStore!
    private var conversation: Conversation!
    private var me: Participant!
    private var anna: Participant!
    private var segments: [Segment] = []
    private let now = Date(timeIntervalSince1970: 1_800_001_000)

    override func setUpWithError() throws {
        database = try LorreDatabase.inMemory()
        let store = ConversationStore(database: database)
        review = ReviewStore(database: database)
        conversation = makeConversation(title: "Call")
        try store.save(conversation)
        me = Participant(conversationId: conversation.id, name: "Thijs", isUser: true)
        anna = Participant(conversationId: conversation.id, name: "Anna")
        try store.saveParticipants([me, anna])
        let version = TranscriptVersion(conversationId: conversation.id, engine: "test")
        segments = [
            Segment(transcriptVersionId: version.id, participantId: me.id, startMs: 1_000, endMs: 4_000, text: "Een."),
            Segment(transcriptVersionId: version.id, participantId: anna.id, startMs: 5_000, endMs: 9_000, text: "Twee."),
            Segment(transcriptVersionId: version.id, participantId: anna.id, startMs: 10_000, endMs: 12_000, text: "Drie."),
        ]
        try store.saveTranscript(version: version, segments: segments)
    }

    private func proposal(_ text: String, kind: OutcomeKind = .theirCommitment, owner: Participant? = nil, evidence: [Segment]) -> ProposedOutcome {
        ProposedOutcome(kind: kind, text: text, ownerParticipantId: owner?.id, evidenceSegmentIds: evidence.map(\.id))
    }

    func testInsertsProposalsWithEvidenceAndModelSource() throws {
        let stored = try review.replaceProposals(
            conversationId: conversation.id,
            proposals: [proposal("Anna belt.", owner: anna, evidence: [segments[1], segments[2]])],
            modelIdentifier: "two-step/fake", now: now
        )
        let outcome = try XCTUnwrap(stored.first)
        XCTAssertEqual(outcome.status, .proposed)
        XCTAssertEqual(outcome.source, .model)
        XCTAssertFalse(outcome.edited)
        XCTAssertEqual(outcome.ownerParticipantId, anna.id)
        XCTAssertEqual(outcome.evidenceSegmentIds, [segments[1].id, segments[2].id])
        XCTAssertEqual(outcome.evidenceStartMs, 5_000)
        XCTAssertEqual(outcome.evidenceEndMs, 12_000)
        XCTAssertEqual(try review.outcomes(conversationId: conversation.id), [outcome])
    }

    func testReplacesUntouchedModelProposalsAndKeepsEverythingElse() throws {
        let old = try review.replaceProposals(
            conversationId: conversation.id,
            proposals: (1...6).map { proposal("Oud \($0).", kind: .decision, evidence: [segments[0]]) },
            modelIdentifier: "m", now: now
        )
        let approved = try review.setStatus(.approved, for: old[0].id, now: now)
        let rejected = try review.setStatus(.rejected, for: old[1].id, now: now)
        let edited = try review.updateOutcome(old[2].id, text: "Aangepast.", now: now)
        XCTAssertTrue(edited.edited)
        let mine = try review.addOutcome(conversationId: conversation.id, kind: .myAction, text: "Eigen.", evidence: [segments[0]], now: now)
        let agent = try review.addOutcome(conversationId: conversation.id, kind: .openPoint, text: "Agent.", source: .agent, now: now)

        let fresh = try review.replaceProposals(
            conversationId: conversation.id,
            proposals: [proposal("Nieuw.", kind: .openPoint, evidence: [segments[2]])],
            modelIdentifier: "m2", now: now
        )

        let all = try review.outcomes(conversationId: conversation.id)
        XCTAssertEqual(Set(all.map(\.id)), Set([approved.id, rejected.id, edited.id, mine.id, agent.id] + fresh.map(\.id)))
        XCTAssertEqual(all.first { $0.id == approved.id }, approved)
        XCTAssertEqual(all.first { $0.id == rejected.id }, rejected)
        XCTAssertEqual(all.first { $0.id == edited.id }, edited)
        XCTAssertEqual(all.first { $0.id == mine.id }, mine)
        XCTAssertEqual(fresh.count, 1)
    }

    func testRunningTwiceDoesNotPileUp() throws {
        for _ in 0..<3 {
            _ = try review.replaceProposals(
                conversationId: conversation.id,
                proposals: [proposal("Een.", kind: .decision, evidence: [segments[0]])],
                modelIdentifier: "m", now: now
            )
        }
        XCTAssertEqual(try review.outcomes(conversationId: conversation.id).count, 1)
    }

    func testInventedEvidenceAndOwnersAreDropped() throws {
        let stranger = UUID()
        let stored = try review.replaceProposals(
            conversationId: conversation.id,
            proposals: [
                ProposedOutcome(kind: .myAction, text: "X.", ownerParticipantId: stranger, evidenceSegmentIds: [UUID(), segments[0].id]),
                ProposedOutcome(kind: .decision, text: "Y.", ownerParticipantId: anna.id, evidenceSegmentIds: []),
                ProposedOutcome(kind: .decision, text: "   ", evidenceSegmentIds: [segments[0].id]),
            ],
            modelIdentifier: "m", now: now
        )
        XCTAssertEqual(stored.count, 2)
        XCTAssertNil(stored[0].ownerParticipantId)
        XCTAssertEqual(stored[0].evidenceSegmentIds, [segments[0].id])
        XCTAssertNil(stored[1].ownerParticipantId, "a decision has no owner")
        XCTAssertNil(stored[1].evidenceStartMs)
    }

    func testUnknownConversationThrows() {
        XCTAssertThrowsError(try review.replaceProposals(conversationId: UUID(), proposals: [], modelIdentifier: "m")) {
            XCTAssertEqual($0 as? ReviewStore.ReviewError, .conversationNotFound)
        }
    }

    func testApprovedConversationBecomesChanged() throws {
        try review.finishReview(conversation.id, now: now)
        _ = try review.replaceProposals(
            conversationId: conversation.id,
            proposals: [proposal("Nieuw.", kind: .decision, evidence: [segments[0]])],
            modelIdentifier: "m", now: now
        )
        XCTAssertEqual(try ConversationStore(database: database).conversation(id: conversation.id)?.state, .changed)
    }
}

final class ProposalEvaluatorTests: XCTestCase {
    private let conversationId = UUID()
    private var me: Participant!
    private var anna: Participant!

    override func setUp() {
        me = Participant(conversationId: conversationId, name: "Thijs", isUser: true)
        anna = Participant(conversationId: conversationId, name: "Anna")
    }

    private func report(_ expected: [EvalReference.Expected], _ proposals: [ProposedOutcome]) -> EvalReport {
        ProposalEvaluator.score(
            reference: EvalReference(conversationId: conversationId.uuidString, expected: expected),
            proposals: proposals, participants: [me, anna]
        )
    }

    func testFoundCorrectAndUnmatched() {
        let result = report(
            [
                .init(kind: "theirCommitment", owner: "Anna", keywords: ["naam", "jimmy"], label: "naam doorgeven"),
                .init(kind: "myAction", owner: "ik", keywords: ["introduc", "bureau"], label: "introductie"),
                .init(kind: "decision", owner: nil, keywords: ["event"], label: "event"),
                .init(kind: "decision", owner: nil, keywords: ["vrijdag", "verhuizing"], label: "gemist"),
            ],
            [
                ProposedOutcome(kind: .theirCommitment, text: "Anna geeft de NAAM door aan Jimmy.", ownerParticipantId: anna.id),
                ProposedOutcome(kind: .theirCommitment, text: "Thijs introduceert Anna bij het bureau.", ownerParticipantId: anna.id),
                ProposedOutcome(kind: .openPoint, text: "Het Évent van vrijdag."),
                ProposedOutcome(kind: .information, text: "Het regent."),
            ]
        )
        XCTAssertEqual(result.items.map(\.found), [true, true, true, false])
        XCTAssertEqual(result.items.map(\.correct), [true, false, false, false])
        XCTAssertEqual(result.proposalCount, 4)
        XCTAssertEqual(result.unmatchedProposalCount, 1)
        XCTAssertEqual(result.recallFound, 0.75)
        XCTAssertEqual(result.recallCorrect, 0.25)
    }

    func testAnyMatchingProposalCanMakeAnItemCorrect() {
        let result = report(
            [.init(kind: "myAction", owner: "ik", keywords: ["offerte"], label: "offerte")],
            [
                ProposedOutcome(kind: .openPoint, text: "Offerte onduidelijk."),
                ProposedOutcome(kind: .myAction, text: "Stuurt de offerte.", ownerParticipantId: me.id),
            ]
        )
        XCTAssertEqual(result.items.first?.correct, true)
        XCTAssertEqual(result.unmatchedProposalCount, 0)
    }

    func testOwnerMustMatchAndMissingOwnerIsWrong() {
        let result = report(
            [.init(kind: "myAction", owner: "Thijs", keywords: ["offerte"], label: "a")],
            [ProposedOutcome(kind: .myAction, text: "Offerte sturen.", ownerParticipantId: nil)]
        )
        XCTAssertEqual(result.items.first?.found, true)
        XCTAssertEqual(result.items.first?.correct, false)
    }

    func testEmptyReferenceAndNoProposals() {
        let result = report([], [])
        XCTAssertEqual(result.recallFound, 0)
        XCTAssertEqual(result.proposalCount, 0)
    }

    func testReferenceFileValidation() throws {
        let good = #"{"conversationId":"AB","expected":[{"kind":"decision","owner":null,"keywords":["x"],"label":"l"},{"kind":"myAction","keywords":["y"]}]}"#
        let reference = try EvalReference.load(from: Data(good.utf8))
        XCTAssertEqual(reference.expected.count, 2)
        XCTAssertEqual(reference.expected[1].title, "y")

        let badKind = #"{"conversationId":"AB","expected":[{"kind":"gossip","keywords":["x"]}]}"#
        XCTAssertThrowsError(try EvalReference.load(from: Data(badKind.utf8))) {
            XCTAssertEqual($0 as? EvalReference.ValidationError, .unknownKind("gossip"))
        }
        let noKeywords = #"{"conversationId":"AB","expected":[{"kind":"decision","keywords":[" "],"label":"leeg"}]}"#
        XCTAssertThrowsError(try EvalReference.load(from: Data(noKeywords.utf8))) {
            XCTAssertEqual($0 as? EvalReference.ValidationError, .noKeywords("leeg"))
        }
        XCTAssertThrowsError(try EvalReference.load(from: Data("{}".utf8)))
    }
}
