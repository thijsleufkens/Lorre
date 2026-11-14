import LorreCore
import XCTest
@testable import Lorre

@MainActor
final class WorkspaceModelTests: XCTestCase {
    private var database: LorreDatabase!
    private var store: ConversationStore!
    private var root: URL!
    private var workspace: WorkspaceModel!
    private var players: [FakeEvidencePlayer] = []

    override func setUp() async throws {
        root = makeTemporaryRoot(named: "workspace")
        database = try LorreDatabase.inMemory()
        store = ConversationStore(database: database)
        players = []
        workspace = WorkspaceModel(database: database, paths: LorrePaths(root: root)) { [unowned self] in
            let player = FakeEvidencePlayer()
            players.append(player)
            return player
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func add(
        _ title: String, state: ConversationState, day: Int, imported: Bool = false
    ) throws -> Conversation {
        let conversation = Conversation(
            title: title, state: state,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400),
            durationSeconds: 60,
            importedAt: imported ? Date(timeIntervalSince1970: 1_800_000_000) : nil
        )
        try store.save(conversation)
        return conversation
    }

    func testListsSplitByStateAndImportedOnesStayOut() throws {
        try add("recording", state: .recording, day: 1)
        try add("processing", state: .processing, day: 2)
        try add("interrupted", state: .interrupted, day: 3)
        try add("proposed old", state: .proposed, day: 4)
        try add("proposed new", state: .proposed, day: 6)
        try add("changed", state: .changed, day: 5)
        try add("approved", state: .approved, day: 7)
        try add("imported proposed", state: .proposed, day: 8, imported: true)
        try add("imported processing", state: .processing, day: 9, imported: true)

        workspace.refresh()

        XCTAssertEqual(workspace.toReview.map(\.conversation.title), ["proposed new", "changed", "proposed old"])
        XCTAssertEqual(workspace.inProgress.map(\.conversation.title), ["interrupted", "processing", "recording"])
        XCTAssertEqual(workspace.all.count, 9)
        XCTAssertEqual(workspace.all.first?.conversation.title, "imported processing", "newest first")
    }

    func testEmptyDatabaseGivesEmptyLists() {
        workspace.refresh()
        XCTAssertTrue(workspace.toReview.isEmpty)
        XCTAssertTrue(workspace.inProgress.isEmpty)
        XCTAssertTrue(workspace.all.isEmpty)
        XCTAssertNil(workspace.errorMessage)
    }

    func testSectionDefaultsToToday() {
        XCTAssertEqual(workspace.section, .today)
        XCTAssertEqual(WorkspaceSection.allCases, [.today, .conversations])
    }

    private func transcribe(_ conversation: Conversation, text: String) throws {
        let version = TranscriptVersion(conversationId: conversation.id, engine: "test")
        try store.saveTranscript(version: version, segments: [
            Segment(transcriptVersionId: version.id, startMs: 0, endMs: 4_000, text: text),
        ])
    }

    func testSearchHitsAppearAndClear() throws {
        let call = try add("Call met Anna", state: .proposed, day: 1)
        try transcribe(call, text: "We praten over de offerte voor Jimmy")

        workspace.searchText = "offerte"
        XCTAssertEqual(workspace.searchHits.map(\.conversationId), [call.id])

        workspace.searchText = "bestaatniet"
        XCTAssertTrue(workspace.searchHits.isEmpty)

        workspace.searchText = "off"
        XCTAssertEqual(workspace.searchHits.count, 1, "the last word may be a prefix")

        workspace.searchText = ""
        XCTAssertTrue(workspace.searchHits.isEmpty)
    }

    func testSearchTextWithoutSearchableWordsGivesNoHits() throws {
        let call = try add("Call", state: .proposed, day: 1)
        try transcribe(call, text: "offerte")
        workspace.searchText = "offerte"
        XCTAssertEqual(workspace.searchHits.count, 1)
        workspace.searchText = " \"* "
        XCTAssertTrue(workspace.searchHits.isEmpty)
        XCTAssertNil(workspace.errorMessage)
    }

    func testOpenCreatesALoadedReviewAndCloseStopsPlayback() throws {
        let call = try add("Call", state: .proposed, day: 1)
        try transcribe(call, text: "hallo")

        workspace.open(call.id)
        let review = try XCTUnwrap(workspace.review)
        XCTAssertEqual(review.conversationID, call.id)
        XCTAssertEqual(review.conversation?.title, "Call")
        XCTAssertEqual(review.segments.count, 1)

        workspace.closeReview()
        XCTAssertNil(workspace.review)
        XCTAssertEqual(players.first?.stopCount, 1)
    }

    func testOpeningAnotherConversationReplacesTheReview() throws {
        let first = try add("First", state: .proposed, day: 1)
        let second = try add("Second", state: .proposed, day: 2)
        workspace.open(first.id)
        workspace.open(second.id)
        XCTAssertEqual(workspace.review?.conversationID, second.id)
        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(players.first?.stopCount, 1)
    }

    func testAConversationFinishedInReviewLeavesToReviewAfterClose() throws {
        let fixture = try ReviewFixture()
        defer { fixture.cleanUp() }
        let workspace = WorkspaceModel(database: fixture.database, paths: fixture.paths) { FakeEvidencePlayer() }
        workspace.refresh()
        XCTAssertEqual(workspace.toReview.map(\.conversation.id), [fixture.conversation.id])
        XCTAssertEqual(workspace.toReview.first?.proposedOutcomes, 4)

        workspace.open(fixture.conversation.id)
        let review = try XCTUnwrap(workspace.review)
        // Point the record at the temp folder so nothing lands in ~/Documents.
        let local = fixture.model()
        local.load()
        XCTAssertTrue(local.finish())
        review.load()

        XCTAssertEqual(workspace.toReview.count, 1, "the lists only change on refresh")
        workspace.closeReview()
        XCTAssertTrue(workspace.toReview.isEmpty)
        XCTAssertEqual(workspace.all.first?.conversation.state, .approved)
    }
}
