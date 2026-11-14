import LorreCore
import XCTest
@testable import Lorre

@MainActor
final class FakeEvidencePlayer: EvidencePlaying {
    struct Call: Equatable {
        var url: URL
        var startMs: Int
        var endMs: Int?
    }

    private(set) var isPlaying = false
    private(set) var calls: [Call] = []
    private(set) var stopCount = 0

    func play(url: URL, startMs: Int, endMs: Int?) {
        calls.append(Call(url: url, startMs: startMs, endMs: endMs))
        isPlaying = true
    }

    func stop() {
        stopCount += 1
        isPlaying = false
    }
}

/// A conversation with a user, one other speaker, five segments and four proposed outcomes.
@MainActor
struct ReviewFixture {
    let root: URL
    let paths: LorrePaths
    let database: LorreDatabase
    let store: ConversationStore
    let conversation: Conversation
    let thijs: Participant
    let anna: Participant
    let segments: [Segment]
    let myAction: Outcome
    let theirCommitment: Outcome
    let decision: Outcome
    let information: Outcome
    var recordFolder: URL { root.appendingPathComponent("records", isDirectory: true) }

    init(state: ConversationState = .proposed, withAudio: Bool = true) throws {
        root = makeTemporaryRoot(named: "review")
        paths = LorrePaths(root: root)
        database = try LorreDatabase.inMemory()
        store = ConversationStore(database: database)
        conversation = Conversation(
            title: "Intake Anna", type: .intake, state: state,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000), durationSeconds: 60
        )
        try store.save(conversation)
        thijs = Participant(conversationId: conversation.id, name: "Thijs", isUser: true, sourceLabel: "S1")
        anna = Participant(conversationId: conversation.id, name: "Anna", sourceLabel: "S2")
        try store.saveParticipants([thijs, anna])

        let version = TranscriptVersion(conversationId: conversation.id, engine: "test")
        let lines: [(Participant, String)] = [
            (anna, "Welkom."), (thijs, "Ik stuur de offerte."), (anna, "Ik bel Jimmy."),
            (thijs, "Dan spreken we dinsdag."), (anna, "Afgesproken, dinsdag."),
        ]
        segments = lines.enumerated().map { index, line in
            Segment(
                transcriptVersionId: version.id, participantId: line.0.id,
                startMs: index * 10_000, endMs: index * 10_000 + 8_000, text: line.1
            )
        }
        try store.saveTranscript(version: version, segments: segments)

        let review = ReviewStore(database: database)
        let id = conversation.id
        myAction = try review.addOutcome(
            conversationId: id, kind: .myAction, text: "Offerte sturen", ownerParticipantId: thijs.id,
            evidence: [segments[1]], source: .model
        )
        theirCommitment = try review.addOutcome(
            conversationId: id, kind: .theirCommitment, text: "Jimmy bellen", ownerParticipantId: anna.id,
            evidence: [segments[2]], source: .model
        )
        decision = try review.addOutcome(
            conversationId: id, kind: .decision, text: "Dinsdag afspreken",
            evidence: [segments[3], segments[4]], source: .model
        )
        information = try review.addOutcome(
            conversationId: id, kind: .information, text: "Algemeen", source: .model
        )

        if withAudio {
            let folder = paths.conversationFolder(id)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 64).write(to: folder.appendingPathComponent("mix.caf"))
            try store.saveTracks([Track(
                conversationId: id, kind: .mix,
                relativePath: paths.relativeTrackPath(id, fileName: "mix.caf")
            )])
        }
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    func model(
        player: any EvidencePlaying = FakeEvidencePlayer(),
        exportFolder: URL? = nil
    ) -> ReviewModel {
        let folder = exportFolder ?? recordFolder
        return ReviewModel(
            conversationID: conversation.id, database: database, paths: paths, player: player,
            exporter: RecordExporter(database: database, folder: { folder }, language: .english),
            language: .english
        )
    }
}

@MainActor
final class ReviewModelTests: XCTestCase {
    private var fixture: ReviewFixture!
    private var player: FakeEvidencePlayer!
    private var model: ReviewModel!

    override func setUp() async throws {
        fixture = try ReviewFixture()
        player = FakeEvidencePlayer()
        model = fixture.model(player: player)
        model.load()
    }

    override func tearDown() async throws {
        fixture.cleanUp()
    }

    // MARK: Loading and grouping

    func testLoadFillsEverything() {
        XCTAssertEqual(model.conversation?.title, "Intake Anna")
        XCTAssertEqual(model.participants.map(\.name), ["Thijs", "Anna"])
        XCTAssertEqual(model.segments.count, 5)
        XCTAssertEqual(model.outcomes.count, 4)
        XCTAssertEqual(model.pendingCount, 4)
        XCTAssertTrue(model.canPlay)
        XCTAssertNil(model.selectedOutcome)
        XCTAssertNil(model.errorMessage)
    }

    func testGroupsFollowDisplayOrderAndLeaveEmptyKindsOut() {
        XCTAssertEqual(model.groups.map(\.kind), [.myAction, .theirCommitment, .decision, .information])
        XCTAssertEqual(model.groups.first?.items, [fixture.myAction])
    }

    func testNameOfUnknownParticipantIsAQuestionMark() {
        XCTAssertEqual(model.name(of: fixture.anna.id), "Anna")
        XCTAssertEqual(model.name(of: nil), "?")
        XCTAssertEqual(model.name(of: UUID()), "?")
    }

    func testCannotPlayWithoutAudio() throws {
        let silent = try ReviewFixture(withAudio: false)
        defer { silent.cleanUp() }
        let other = silent.model()
        other.load()
        XCTAssertFalse(other.canPlay)
        other.select(silent.myAction.id)
        other.playEvidence()
        XCTAssertTrue(player.calls.isEmpty)
    }

    // MARK: Navigation

    func testNextAndPreviousStopAtTheEnds() {
        model.selectNext()
        XCTAssertEqual(model.selectedOutcomeID, fixture.myAction.id)
        model.selectPrevious()
        XCTAssertEqual(model.selectedOutcomeID, fixture.myAction.id, "stops at the start")
        model.selectNext(); model.selectNext(); model.selectNext()
        XCTAssertEqual(model.selectedOutcomeID, fixture.information.id)
        model.selectNext()
        XCTAssertEqual(model.selectedOutcomeID, fixture.information.id, "stops at the end")
        model.selectPrevious()
        XCTAssertEqual(model.selectedOutcomeID, fixture.decision.id)
    }

    func testSelectPreviousWithoutSelectionStartsAtTheLast() {
        model.selectPrevious()
        XCTAssertEqual(model.selectedOutcomeID, fixture.information.id)
    }

    // MARK: Judging

    func testApproveMovesToTheNextPendingOutcome() {
        model.select(fixture.myAction.id)
        model.approveSelected()
        XCTAssertEqual(model.outcomes.first { $0.id == fixture.myAction.id }?.status, .approved)
        XCTAssertEqual(model.selectedOutcomeID, fixture.theirCommitment.id)
        XCTAssertEqual(model.pendingCount, 3)
    }

    func testApproveSkipsApprovedOnesAndWrapsAround() {
        model.select(fixture.theirCommitment.id)
        model.approveSelected()
        model.select(fixture.information.id)
        model.approveSelected()
        XCTAssertEqual(model.selectedOutcomeID, fixture.myAction.id, "wraps to the first pending one")
    }

    func testApproveLastPendingKeepsSelection() {
        for outcome in [fixture.myAction, fixture.theirCommitment, fixture.decision] {
            model.select(outcome.id)
            model.approveSelected()
        }
        model.select(fixture.information.id)
        model.approveSelected()
        XCTAssertEqual(model.pendingCount, 0)
        XCTAssertEqual(model.selectedOutcomeID, fixture.information.id)
    }

    func testRejectRemovesAndSelectsTheNext() {
        model.select(fixture.myAction.id)
        model.rejectSelected()
        XCTAssertFalse(model.outcomes.contains { $0.id == fixture.myAction.id })
        XCTAssertEqual(model.selectedOutcomeID, fixture.theirCommitment.id)
        XCTAssertEqual(model.groups.map(\.kind), [.theirCommitment, .decision, .information])
    }

    func testRejectTheLastSelectsThePrevious() {
        model.select(fixture.information.id)
        model.rejectSelected()
        XCTAssertEqual(model.selectedOutcomeID, fixture.decision.id)
    }

    func testDeleteRefusesAModelProposal() {
        model.select(fixture.myAction.id)
        model.deleteSelected()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.outcomes.contains { $0.id == fixture.myAction.id })
    }

    func testDeleteRemovesOwnOutcome() {
        model.addOutcome(kind: .openPoint, text: "Prijs bespreken")
        let added = model.selectedOutcomeID
        XCTAssertNotNil(added)
        model.deleteSelected()
        XCTAssertFalse(model.outcomes.contains { $0.id == added })
        XCTAssertNil(model.errorMessage)
    }

    func testRemoveDeletesOwnOutcomeAndRejectsAProposal() throws {
        model.addOutcome(kind: .openPoint, text: "Prijs bespreken")
        let added = try XCTUnwrap(model.selectedOutcomeID)
        model.removeSelected()
        let store = ReviewStore(database: fixture.database)
        let all = try store.outcomes(conversationId: model.conversationID, includingRejected: true)
        XCTAssertFalse(all.contains { $0.id == added })

        model.select(fixture.myAction.id)
        model.removeSelected()
        let after = try store.outcomes(conversationId: model.conversationID, includingRejected: true)
        XCTAssertEqual(after.first { $0.id == fixture.myAction.id }?.status, .rejected)
        XCTAssertNil(model.errorMessage)
    }

    func testUpdateSelectedChangesTextAndFlagsAnEditedProposal() {
        model.select(fixture.myAction.id)
        model.updateSelected(text: "Offerte morgen sturen")
        XCTAssertEqual(model.selectedOutcome?.text, "Offerte morgen sturen")
        XCTAssertEqual(model.selectedOutcome?.edited, true)
        model.updateSelected(owner: .some(nil))
        XCTAssertNil(model.selectedOutcome?.ownerParticipantId)
    }

    func testUpdateWithoutSelectionDoesNothing() {
        model.updateSelected(text: "x")
        XCTAssertEqual(model.outcomes.map(\.text), ["Offerte sturen", "Jimmy bellen", "Dinsdag afspreken", "Algemeen"])
    }

    // MARK: Adding

    func testAddWithSelectionTakesEvidenceAndClearsIt() {
        model.selectedSegmentIDs = [fixture.segments[3].id, fixture.segments[4].id]
        model.addOutcome(kind: .openPoint, text: "  Prijs  ")
        let added = model.selectedOutcome
        XCTAssertEqual(added?.text, "Prijs")
        XCTAssertEqual(added?.source, .user)
        XCTAssertEqual(added?.status, .approved)
        XCTAssertEqual(Set(added?.evidenceSegmentIds ?? []), [fixture.segments[3].id, fixture.segments[4].id])
        XCTAssertEqual(added?.evidenceStartMs, 30_000)
        XCTAssertEqual(added?.evidenceEndMs, 48_000)
        XCTAssertTrue(model.selectedSegmentIDs.isEmpty)
    }

    func testMyActionDefaultsToTheUser() {
        model.selectedSegmentIDs = [fixture.segments[2].id]
        model.addOutcome(kind: .myAction, text: "Terugbellen")
        XCTAssertEqual(model.selectedOutcome?.ownerParticipantId, fixture.thijs.id)
    }

    func testTheirCommitmentDefaultsToTheSpeakerOfTheFirstSegment() {
        model.selectedSegmentIDs = [fixture.segments[4].id, fixture.segments[2].id]
        model.addOutcome(kind: .theirCommitment, text: "Jimmy bellen")
        XCTAssertEqual(model.selectedOutcome?.ownerParticipantId, fixture.anna.id)
    }

    func testTheirCommitmentWithTheUsersSegmentHasNoDefaultOwner() {
        model.selectedSegmentIDs = [fixture.segments[1].id]
        model.addOutcome(kind: .theirCommitment, text: "Iets")
        XCTAssertNil(model.selectedOutcome?.ownerParticipantId)
    }

    func testAddWithoutSelectionHasNoEvidence() {
        model.addOutcome(kind: .decision, text: "Doorgaan")
        XCTAssertEqual(model.selectedOutcome?.evidenceSegmentIds, [])
        XCTAssertTrue(model.evidenceSegments.isEmpty)
    }

    func testBlankTextIsRefused() {
        model.selectedSegmentIDs = [fixture.segments[0].id]
        model.addOutcome(kind: .decision, text: "   \n ")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.outcomes.count, 4)
        XCTAssertEqual(model.selectedSegmentIDs, [fixture.segments[0].id], "the selection survives")
    }

    func testASuccessfulCallClearsTheError() {
        model.addOutcome(kind: .decision, text: " ")
        XCTAssertNotNil(model.errorMessage)
        model.addOutcome(kind: .decision, text: "Wel iets")
        XCTAssertNil(model.errorMessage)
    }

    // MARK: Conversation and people

    func testTitleAndType() {
        model.setTitle("Nieuwe titel")
        model.setType(.network)
        XCTAssertEqual(model.conversation?.title, "Nieuwe titel")
        XCTAssertEqual(model.conversation?.type, .network)
    }

    func testRenameMergeAndSetUserAreReflectedAfterReload() throws {
        model.rename(fixture.anna.id, to: "Anna de Vries")
        XCTAssertEqual(model.name(of: fixture.anna.id), "Anna de Vries")

        let third = Participant(conversationId: fixture.conversation.id, name: "Speaker S3")
        try fixture.store.saveParticipants([third])
        model.load()
        XCTAssertEqual(model.participants.count, 2, "a label nobody speaks under is left out")
        model.merge(third.id, into: fixture.anna.id)
        XCTAssertEqual(model.participants.map(\.name), ["Thijs", "Anna de Vries"])

        model.setUser(fixture.anna.id)
        XCTAssertEqual(model.participants.map(\.name), ["Anna de Vries", "Thijs"])
        XCTAssertEqual(model.participants.first?.isUser, true)
    }

    func testMergeWithItselfShowsAnError() {
        model.merge(fixture.anna.id, into: fixture.anna.id)
        XCTAssertNotNil(model.errorMessage)
    }

    func testAssignSegment() {
        model.assign(segmentID: fixture.segments[0].id, to: fixture.thijs.id)
        XCTAssertEqual(model.segments[0].participantId, fixture.thijs.id)
        XCTAssertTrue(model.segments[0].isEdited)
    }

    func testEditsKeepTheSelectedOutcome() {
        model.select(fixture.decision.id)
        model.rename(fixture.anna.id, to: "Anna B")
        model.setTitle("Anders")
        XCTAssertEqual(model.selectedOutcomeID, fixture.decision.id)
    }

    // MARK: Evidence

    func testEvidenceHasOneSegmentOfContextOnEachSide() {
        model.select(fixture.theirCommitment.id)
        XCTAssertEqual(model.evidenceSegments.map(\.id), fixture.segments[1...3].map(\.id))
    }

    func testEvidenceContextIsClampedAtTheEnds() {
        model.select(fixture.decision.id)   // segments 3 and 4: the last two
        XCTAssertEqual(model.evidenceSegments.map(\.id), fixture.segments[2...4].map(\.id))

        model.addOutcome(kind: .decision, text: "Eerste")
        model.selectedSegmentIDs = [fixture.segments[0].id]
        model.addOutcome(kind: .openPoint, text: "Begin")
        XCTAssertEqual(model.evidenceSegments.map(\.id), fixture.segments[0...1].map(\.id))
    }

    func testEvidenceIsEmptyWithoutSelectionOrWithoutEvidence() {
        XCTAssertTrue(model.evidenceSegments.isEmpty)
        model.select(fixture.information.id)
        XCTAssertTrue(model.evidenceSegments.isEmpty)
    }

    // MARK: Playback

    func testPlayEvidenceUsesTheOutcomesRangeAndTheLocatedFile() {
        model.select(fixture.decision.id)
        model.playEvidence()
        XCTAssertEqual(player.calls, [.init(
            url: fixture.paths.conversationFolder(fixture.conversation.id).appendingPathComponent("mix.caf"),
            startMs: 30_000, endMs: 48_000
        )])
    }

    func testPlayEvidenceWithoutSelectionOrEvidenceIsANoOp() {
        model.playEvidence()
        model.select(fixture.information.id)
        model.playEvidence()
        XCTAssertTrue(player.calls.isEmpty)
    }

    func testPlaySegmentPlaysToTheEnd() {
        model.play(segmentID: fixture.segments[2].id)
        XCTAssertEqual(player.calls.map(\.startMs), [20_000])
        XCTAssertEqual(player.calls.map(\.endMs), [nil])
        model.stopPlayback()
        XCTAssertEqual(player.stopCount, 1)
        XCTAssertFalse(player.isPlaying)
    }

    // MARK: Finishing

    func testFinishApprovesPendingAndWritesTheRecord() throws {
        XCTAssertTrue(model.finish())
        XCTAssertTrue(model.isFinished)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.pendingCount, 0)
        XCTAssertEqual(model.conversation?.state, .approved)

        let exported = try XCTUnwrap(model.lastExport)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.json.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.markdown.path))
        XCTAssertEqual(exported.json.deletingLastPathComponent().standardizedFileURL, fixture.recordFolder.standardizedFileURL)
        let record = try MeetingRecord.decoder().decode(MeetingRecord.self, from: Data(contentsOf: exported.json))
        XCTAssertEqual(record.status, .approved)
        XCTAssertEqual(record.recordVersion, 1)
        XCTAssertEqual(record.outcomes.count, 4)
    }

    func testFinishLeavesRejectedOutcomesOutOfTheRecord() throws {
        model.select(fixture.information.id)
        model.rejectSelected()
        XCTAssertTrue(model.finish())
        XCTAssertEqual(try XCTUnwrap(model.lastExport).record.outcomes.count, 3)
    }

    func testFinishWithAnUnwritableFolderKeepsTheApproval() throws {
        let blocked = fixture.root.appendingPathComponent("blocked")
        try Data("file".utf8).write(to: blocked)
        let failing = fixture.model(player: player, exportFolder: blocked)
        failing.load()

        XCTAssertFalse(failing.finish())
        XCTAssertFalse(failing.isFinished)
        XCTAssertNotNil(failing.errorMessage)
        XCTAssertNil(failing.lastExport)
        XCTAssertEqual(failing.conversation?.state, .approved)
        XCTAssertEqual(failing.pendingCount, 0)
    }

    func testEditingAfterFinishMakesItChangedAndTheSecondFinishWritesVersionTwo() throws {
        XCTAssertTrue(model.finish())
        model.setTitle("Aangepaste titel")
        XCTAssertFalse(model.isFinished)
        XCTAssertEqual(model.conversation?.state, .changed)

        XCTAssertTrue(model.finish())
        XCTAssertTrue(model.isFinished)
        XCTAssertEqual(model.conversation?.state, .approved)
        let exported = try XCTUnwrap(model.lastExport)
        XCTAssertEqual(exported.record.recordVersion, 2)
        XCTAssertEqual(exported.record.conversation.title, "Aangepaste titel")
    }

    // MARK: People

    /// A second conversation with a person called "Anna Jansen", so "Anna" has a suggestion.
    @discardableResult
    private func addPersonAnnaJansen() throws -> Person {
        let other = Conversation(title: "Eerder", state: .approved, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try fixture.store.save(other)
        let participant = Participant(conversationId: other.id, name: "Anna Jansen")
        try fixture.store.saveParticipants([participant])
        return try PeopleStore(database: fixture.database).createPerson(from: participant.id)
    }

    func testSaveAsPersonLinksTheParticipant() throws {
        XCTAssertTrue(model.canSaveAsPerson(fixture.anna))
        model.saveAsPerson(fixture.anna.id)

        XCTAssertNil(model.errorMessage)
        let anna = try XCTUnwrap(model.participants.first { $0.id == fixture.anna.id })
        XCTAssertNotNil(anna.personId)
        XCTAssertEqual(model.person(of: anna)?.name, "Anna")
        XCTAssertFalse(model.canSaveAsPerson(anna), "already linked")
        XCTAssertEqual(try PeopleStore(database: fixture.database).people().count, 1)
    }

    func testTheUserAndStandInNamesCannotBeSavedAsPerson() throws {
        XCTAssertFalse(model.canSaveAsPerson(fixture.thijs))
        model.rename(fixture.anna.id, to: "Spreker 2")
        let renamed = try XCTUnwrap(model.participants.first { $0.id == fixture.anna.id })
        XCTAssertFalse(model.canSaveAsPerson(renamed))

        model.saveAsPerson(fixture.thijs.id)
        XCTAssertNotNil(model.errorMessage, "the store refuses the user")
        XCTAssertNil(model.person(of: fixture.thijs))
    }

    func testSuggestionsLinkAndUnlink() throws {
        let jansen = try addPersonAnnaJansen()
        model.load()
        XCTAssertEqual(model.personSuggestions(for: fixture.anna.id).map(\.name), ["Anna Jansen"])
        XCTAssertTrue(model.personSuggestions(for: fixture.thijs.id).isEmpty)

        model.link(fixture.anna.id, to: jansen.id)
        let linked = try XCTUnwrap(model.participants.first { $0.id == fixture.anna.id })
        XCTAssertEqual(model.person(of: linked)?.id, jansen.id)
        XCTAssertTrue(model.personSuggestions(for: fixture.anna.id).isEmpty, "the linked person is no suggestion")

        model.unlink(fixture.anna.id)
        let unlinked = try XCTUnwrap(model.participants.first { $0.id == fixture.anna.id })
        XCTAssertNil(unlinked.personId)
        XCTAssertNil(model.person(of: unlinked))
        XCTAssertEqual(model.personSuggestions(for: fixture.anna.id).count, 1)
    }

    func testLinkingToAPersonThatIsGoneReportsAnError() {
        model.link(fixture.anna.id, to: UUID())
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.participants.first { $0.id == fixture.anna.id }?.personId)
    }

    func testShowPersonReportsTheLinkedPersonOnly() throws {
        var shown: [UUID] = []
        model.onShowPerson = { shown.append($0) }

        model.showPerson(of: fixture.anna.id)
        XCTAssertTrue(shown.isEmpty, "not linked")

        model.saveAsPerson(fixture.anna.id)
        model.showPerson(of: fixture.anna.id)
        let personID = try XCTUnwrap(model.participants.first { $0.id == fixture.anna.id }?.personId)
        XCTAssertEqual(shown, [personID])
    }
}
