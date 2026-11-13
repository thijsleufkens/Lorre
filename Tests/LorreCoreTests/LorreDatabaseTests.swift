import GRDB
import XCTest
@testable import LorreCore

final class LorreDatabaseTests: XCTestCase {
    func testMigrationCreatesEveryTable() throws {
        let tables = try LorreDatabase.inMemory().tableNames()
        for name in [
            "conversation", "person", "participant", "track", "transcriptVersion",
            "segment", "outcome", "recordExport", "consumerCursor", "segmentSearch",
        ] {
            XCTAssertTrue(tables.contains(name), "missing table \(name)")
        }
    }

    func testReopeningAFileKeepsItsData() throws {
        let root = try TemporaryRoot()
        let conversation = makeConversation()
        try ConversationStore(database: LorreDatabase(url: root.paths.database)).save(conversation)

        let reopened = ConversationStore(database: try LorreDatabase(url: root.paths.database))
        XCTAssertEqual(try reopened.conversation(id: conversation.id), conversation)
    }

    func testOpeningCreatesTheParentFolder() throws {
        let root = try TemporaryRoot()
        let nested = root.paths.root.appendingPathComponent("a/b/lorre.sqlite")
        _ = try LorreDatabase(url: nested)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testIdsAreStoredAsUppercaseText() throws {
        let database = try LorreDatabase.inMemory()
        let conversation = makeConversation()
        try ConversationStore(database: database).save(conversation)
        let stored = try database.queue.read { db in try String.fetchOne(db, sql: "SELECT id FROM conversation") }
        XCTAssertEqual(stored, conversation.id.uuidString)
    }

    func testDeletingAConversationRemovesItsChildren() throws {
        let database = try LorreDatabase.inMemory()
        let store = ConversationStore(database: database)
        let conversation = makeConversation()
        try store.save(conversation)
        let participant = Participant(conversationId: conversation.id, name: "A")
        try store.saveParticipants([participant])
        try store.saveTracks([Track(conversationId: conversation.id, kind: .mix, relativePath: "x/audio.caf")])
        let version = TranscriptVersion(conversationId: conversation.id, engine: "test")
        let segment = Segment(
            transcriptVersionId: version.id, participantId: participant.id, startMs: 0, endMs: 10, text: "hallo"
        )
        try store.saveTranscript(version: version, segments: [segment])
        try database.queue.write { db in
            try Outcome(
                conversationId: conversation.id, kind: .myAction, text: "Doen", source: .user,
                evidenceSegmentIds: [segment.id]
            ).insert(db)
            try RecordExport(conversationId: conversation.id, version: 1, status: .draft, path: "r.json").insert(db)
            try ConsumerCursor(consumerName: "agent", conversationId: conversation.id, recordVersion: 1).insert(db)
        }

        try store.delete(conversationId: conversation.id)

        try database.queue.read { db in
            for table in [
                "participant", "track", "transcriptVersion", "segment", "outcome", "recordExport", "consumerCursor",
            ] {
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)"), 0, table)
            }
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM segmentSearch"), 0)
        }
    }

    func testSegmentNeedsAnExistingTranscriptVersion() throws {
        let database = try LorreDatabase.inMemory()
        XCTAssertThrowsError(try database.queue.write { db in
            try Segment(transcriptVersionId: UUID(), startMs: 0, endMs: 1, text: "x").insert(db)
        })
    }

    func testOutcomeRoundTripsItsEvidence() throws {
        let database = try LorreDatabase.inMemory()
        let conversation = makeConversation()
        try ConversationStore(database: database).save(conversation)
        let outcome = Outcome(
            conversationId: conversation.id, kind: .theirCommitment, text: "Stuurt de link",
            due: Date(timeIntervalSince1970: 1_800_086_400), status: .approved, edited: true, source: .model,
            evidenceSegmentIds: [UUID(), UUID()], evidenceStartMs: 1000, evidenceEndMs: 2000,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let fetched = try database.queue.write { db -> Outcome? in
            try outcome.insert(db)
            return try Outcome.fetchOne(db, key: outcome.id.uuidString)
        }
        XCTAssertEqual(fetched, outcome)
    }
}
