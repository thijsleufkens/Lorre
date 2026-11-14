import XCTest
@testable import LorreCore

/// Builds a database with conversations whose records were really exported to a temp folder.
final class RecordFixture {
    let root: TemporaryRoot
    let folder: URL
    let database: LorreDatabase
    let store: ConversationStore
    let review: ReviewStore
    let exporter: RecordExporter

    init() throws {
        root = try TemporaryRoot()
        folder = root.paths.root.appendingPathComponent("records", isDirectory: true)
        database = try LorreDatabase.inMemory()
        store = ConversationStore(database: database)
        review = ReviewStore(database: database)
        let folder = self.folder
        exporter = RecordExporter(
            database: database, folder: { folder }, language: .english,
            now: { Date(timeIntervalSince1970: 1_791_460_000) }
        )
    }

    /// A conversation with a two-segment transcript; `startedAt` decides the order in listings.
    @discardableResult
    func addConversation(
        id: UUID = UUID(), title: String, startedAt: TimeInterval, state: ConversationState = .proposed
    ) throws -> Conversation {
        let conversation = Conversation(
            id: id, title: title, type: .network, state: state,
            startedAt: Date(timeIntervalSince1970: startedAt), durationSeconds: 120
        )
        try store.save(conversation)
        let thijs = Participant(conversationId: id, name: "Thijs", isUser: true)
        let anna = Participant(conversationId: id, name: "Anna")
        try store.saveParticipants([thijs, anna])
        let version = TranscriptVersion(conversationId: id, engine: "test-engine")
        try store.saveTranscript(version: version, segments: [
            Segment(transcriptVersionId: version.id, participantId: thijs.id, startMs: 1_000, endMs: 4_000, text: "Ik stuur de offerte."),
            Segment(transcriptVersionId: version.id, participantId: anna.id, startMs: 65_000, endMs: 69_000, text: "Dan geef ik je naam door."),
        ])
        return conversation
    }

    /// Adds one approved outcome so the approved record has something in it.
    func approve(_ conversation: Conversation) throws {
        try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "We doen het", source: .user)
        try review.finishReview(conversation.id)
        try exporter.exportApproved(conversation.id)
    }
}

final class RecordCatalogTests: XCTestCase {
    private var fixture: RecordFixture!
    private var catalog: RecordCatalog!

    override func setUpWithError() throws {
        fixture = try RecordFixture()
        catalog = RecordCatalog(database: fixture.database)
    }

    func testEmptyDatabaseListsNothing() throws {
        XCTAssertEqual(try catalog.list(), [])
    }

    func testListsLatestVersionNewestConversationFirst() throws {
        let older = try fixture.addConversation(title: "Older", startedAt: 1_791_000_000)
        let newer = try fixture.addConversation(title: "Newer", startedAt: 1_791_100_000)
        try fixture.exporter.exportDraft(older.id)
        try fixture.approve(newer)
        try fixture.review.updateConversation(newer.id, title: "Newer renamed")
        try fixture.approve(newer)

        let listings = try catalog.list()

        XCTAssertEqual(listings.map(\.title), ["Newer renamed", "Older"])
        XCTAssertEqual(listings[0].recordId, newer.id)
        XCTAssertEqual(listings[0].recordVersion, 2)
        XCTAssertEqual(listings[0].status, .approved)
        XCTAssertEqual(listings[0].approvedAt, Date(timeIntervalSince1970: 1_791_460_000))
        XCTAssertEqual(listings[1].status, .draft)
        XCTAssertEqual(listings[1].recordVersion, 0)
        XCTAssertNil(listings[1].approvedAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: listings[0].path))
        XCTAssertEqual(listings[0].startedAt, Date(timeIntervalSince1970: 1_791_100_000))
    }

    func testConversationWithoutExportIsNotListed() throws {
        try fixture.addConversation(title: "Never exported", startedAt: 1_791_000_000)
        XCTAssertEqual(try catalog.list(), [])
    }

    func testStatusFilter() throws {
        let draft = try fixture.addConversation(title: "Draft", startedAt: 1_791_000_000)
        let approved = try fixture.addConversation(title: "Approved", startedAt: 1_791_100_000)
        try fixture.exporter.exportDraft(draft.id)
        try fixture.approve(approved)

        XCTAssertEqual(try catalog.list(status: .draft).map(\.title), ["Draft"])
        XCTAssertEqual(try catalog.list(status: .approved).map(\.title), ["Approved"])
        XCTAssertEqual(try catalog.list(status: nil).count, 2)
    }

    func testNewForLeavesOutWhatTheConsumerMarked() throws {
        let first = try fixture.addConversation(title: "First", startedAt: 1_791_000_000)
        let second = try fixture.addConversation(title: "Second", startedAt: 1_791_100_000)
        try fixture.approve(first)
        try fixture.approve(second)
        try ConsumerStore(database: fixture.database).markProcessed(recordId: first.id, consumer: "agent")

        XCTAssertEqual(try catalog.list(newFor: "agent").map(\.title), ["Second"])
        XCTAssertEqual(try catalog.list(newFor: "someone else").count, 2)
        XCTAssertEqual(try catalog.list().count, 2)
    }

    func testReApprovedRecordIsNewAgain() throws {
        let conversation = try fixture.addConversation(title: "Call", startedAt: 1_791_000_000)
        try fixture.approve(conversation)
        try ConsumerStore(database: fixture.database).markProcessed(recordId: conversation.id, consumer: "agent")
        XCTAssertEqual(try catalog.list(newFor: "agent"), [])

        try fixture.review.addOutcome(conversationId: conversation.id, kind: .decision, text: "Nog iets", source: .user)
        try fixture.review.finishReview(conversation.id)
        try fixture.exporter.exportApproved(conversation.id)

        let again = try catalog.list(newFor: "agent")
        XCTAssertEqual(again.map(\.recordVersion), [2])
    }

    func testRecordReadsTheFileFromDisk() throws {
        let conversation = try fixture.addConversation(title: "Call", startedAt: 1_791_000_000)
        try fixture.approve(conversation)

        let record = try catalog.record(conversation.id)

        XCTAssertEqual(record.recordId, conversation.id)
        XCTAssertEqual(record.status, .approved)
        XCTAssertEqual(record.outcomes.map(\.text), ["We doen het"])
        XCTAssertEqual(record.transcript.segments.count, 2)
    }

    func testRecordWithMissingFileThrowsClearError() throws {
        let conversation = try fixture.addConversation(title: "Call", startedAt: 1_791_000_000)
        try fixture.approve(conversation)
        let listing = try XCTUnwrap(try catalog.list().first)
        try FileManager.default.removeItem(atPath: listing.path)

        XCTAssertThrowsError(try catalog.record(conversation.id)) { error in
            XCTAssertEqual(error as? RecordCatalogError, .fileMissing(path: listing.path))
            XCTAssertTrue((error as? LocalizedError)?.errorDescription?.contains("gone") == true)
        }
    }

    func testRecordOfUnknownIdThrows() throws {
        XCTAssertThrowsError(try catalog.record(UUID())) { error in
            guard case RecordCatalogError.noRecordWithPrefix = error else { return XCTFail("\(error)") }
        }
    }

    func testResolvePrefix() throws {
        let a = RecordListing(
            recordId: UUID(uuidString: "AAAA1111-0000-0000-0000-000000000000")!, recordVersion: 1, status: .approved,
            title: "A", type: .network, startedAt: Date(), path: "/a"
        )
        let b = RecordListing(
            recordId: UUID(uuidString: "AAAA2222-0000-0000-0000-000000000000")!, recordVersion: 1, status: .approved,
            title: "B", type: .network, startedAt: Date(), path: "/b"
        )
        XCTAssertEqual(try RecordCatalog.resolve("aaaa1", in: [a, b]), a)
        XCTAssertEqual(try RecordCatalog.resolve(a.recordId.uuidString, in: [a, b]), a)
        XCTAssertThrowsError(try RecordCatalog.resolve("aaaa", in: [a, b])) { error in
            XCTAssertEqual(error as? RecordCatalogError, .ambiguousPrefix("aaaa", count: 2))
        }
        XCTAssertThrowsError(try RecordCatalog.resolve("ffff", in: [a, b])) { error in
            XCTAssertEqual(error as? RecordCatalogError, .noRecordWithPrefix("ffff"))
        }
        XCTAssertThrowsError(try RecordCatalog.resolve("  ", in: [a, b]))
    }
}
