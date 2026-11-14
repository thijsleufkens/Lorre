import LorreCore
import XCTest
@testable import Lorre

private struct FixedProposer: OutcomeProposer {
    let identifier = "fixed"
    let evidence: UUID
    let fails: Bool
    func propose(_ input: ProposalInput) async throws -> [ProposedOutcome] {
        if fails { throw CocoaError(.fileNoSuchFile) }
        return [ProposedOutcome(kind: .decision, text: "We gaan door.", ownerParticipantId: nil, evidenceSegmentIds: [evidence])]
    }
}

@MainActor
final class ProposalRunnerTests: XCTestCase {
    private var fixture: ReviewFixture!

    override func setUp() async throws { fixture = try ReviewFixture() }
    override func tearDown() async throws { fixture.cleanUp() }

    private func runner(fails: Bool = false) -> ProposalRunner {
        let evidence = fixture.segments[0].id
        return ProposalRunner(database: fixture.database, makeProposer: { _ in FixedProposer(evidence: evidence, fails: fails) })
    }

    func testDoesNothingWithoutAModel() async throws {
        let stored = await runner().run(fixture.conversation.id)
        XCTAssertNil(stored)
    }

    func testStoresProposalsWhenAModelIsSet() async throws {
        try SettingsStore(database: fixture.database).set("some-model", for: .proposalModel)
        let stored = await runner().run(fixture.conversation.id)
        XCTAssertEqual(stored, 1)
        let outcomes = try ReviewStore(database: fixture.database)
            .outcomes(conversationId: fixture.conversation.id, includingRejected: false)
        XCTAssertTrue(outcomes.contains { $0.text == "We gaan door." && $0.status == .proposed })
    }

    func testAFailingModelIsNotAnError() async throws {
        try SettingsStore(database: fixture.database).set("some-model", for: .proposalModel)
        let before = try ReviewStore(database: fixture.database)
            .outcomes(conversationId: fixture.conversation.id, includingRejected: true)
        let stored = await runner(fails: true).run(fixture.conversation.id)
        XCTAssertNil(stored)
        let after = try ReviewStore(database: fixture.database)
            .outcomes(conversationId: fixture.conversation.id, includingRejected: true)
        XCTAssertEqual(before, after)
    }
}

final class PlainSpeakerNamesTests: XCTestCase {
    func testStandInNamesBecomePlainAndGivenNamesStay() {
        let document = TranscriptDocument(
            sessionId: UUID(), sourceEngine: "test", segments: [],
            speakers: [
                SpeakerProfile(id: "S1", displayName: "Speaker S1", styleVariant: .filled, isUserRenamed: false),
                SpeakerProfile(id: "UNK", displayName: "Unknown speaker", styleVariant: .filled, isUserRenamed: false),
                SpeakerProfile(id: "S2", displayName: "Anna", styleVariant: .filled, isUserRenamed: true),
            ]
        )
        let dutch = ConversationProcessor.withPlainSpeakerNames(document, language: .dutch)
        XCTAssertEqual(dutch.speakers.map(\.displayName), ["Spreker 1", "Onbekend", "Anna"])
        let english = ConversationProcessor.withPlainSpeakerNames(document, language: .english)
        XCTAssertEqual(english.speakers.map(\.displayName), ["Speaker 1", "Unknown", "Anna"])
    }
}
