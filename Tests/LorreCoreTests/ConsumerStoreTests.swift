import XCTest
@testable import LorreCore

final class ConsumerStoreTests: XCTestCase {
    private var fixture: RecordFixture!
    private var consumers: ConsumerStore!
    private var conversation: Conversation!
    private let moment = Date(timeIntervalSince1970: 1_791_500_000)

    override func setUpWithError() throws {
        fixture = try RecordFixture()
        consumers = ConsumerStore(database: fixture.database)
        conversation = try fixture.addConversation(title: "Call", startedAt: 1_791_000_000)
        try fixture.approve(conversation)
    }

    func testMarksTheLatestVersionByDefault() throws {
        let cursor = try consumers.markProcessed(recordId: conversation.id, consumer: "agent", now: moment)

        XCTAssertEqual(cursor.recordVersion, 1)
        XCTAssertEqual(cursor.consumerName, "agent")
        XCTAssertEqual(cursor.conversationId, conversation.id)
        XCTAssertEqual(try consumers.cursors(consumer: "agent"), [cursor])
        XCTAssertEqual(try consumers.cursors(consumer: "other"), [])
    }

    func testMarkingTwiceIsFine() throws {
        try consumers.markProcessed(recordId: conversation.id, consumer: "agent", now: moment)
        try consumers.markProcessed(recordId: conversation.id, consumer: "agent", now: moment.addingTimeInterval(60))

        let cursors = try consumers.cursors(consumer: "agent")
        XCTAssertEqual(cursors.count, 1)
        XCTAssertEqual(cursors[0].processedAt, moment.addingTimeInterval(60))
    }

    func testExplicitEarlierVersion() throws {
        try fixture.review.addOutcome(conversationId: conversation.id, kind: .decision, text: "Nog iets", source: .user)
        try fixture.review.finishReview(conversation.id)
        try fixture.exporter.exportApproved(conversation.id)

        try consumers.markProcessed(recordId: conversation.id, version: 1, consumer: "agent", now: moment)

        XCTAssertEqual(try consumers.cursors(consumer: "agent").map(\.recordVersion), [1])
        XCTAssertEqual(try RecordCatalog(database: fixture.database).list(newFor: "agent").map(\.recordVersion), [2])
    }

    func testConsumerNameIsTrimmedAndBlankIsRefused() throws {
        let cursor = try consumers.markProcessed(recordId: conversation.id, consumer: "  agent ", now: moment)
        XCTAssertEqual(cursor.consumerName, "agent")
        XCTAssertThrowsError(try consumers.markProcessed(recordId: conversation.id, consumer: "   ")) {
            XCTAssertEqual($0 as? ConsumerError, .blankConsumer)
        }
    }

    func testUnknownRecordAndVersionAreRefused() throws {
        let unknown = UUID()
        XCTAssertThrowsError(try consumers.markProcessed(recordId: unknown, consumer: "agent")) {
            XCTAssertEqual($0 as? ConsumerError, .noSuchRecord(unknown))
        }
        XCTAssertThrowsError(try consumers.markProcessed(recordId: conversation.id, version: 7, consumer: "agent")) {
            XCTAssertEqual($0 as? ConsumerError, .noSuchVersion(conversation.id, 7))
        }
        XCTAssertEqual(try consumers.cursors(consumer: "agent"), [])
    }
}
