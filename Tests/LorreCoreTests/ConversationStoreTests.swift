import XCTest
@testable import LorreCore

final class ConversationStoreTests: XCTestCase {
    private var database: LorreDatabase!
    private var store: ConversationStore!

    override func setUpWithError() throws {
        database = try LorreDatabase.inMemory()
        store = ConversationStore(database: database)
    }

    func testSaveRoundTripsEveryField() throws {
        var conversation = makeConversation()
        conversation.importedAt = Date(timeIntervalSince1970: 1_800_000_500)
        try store.save(conversation)
        XCTAssertEqual(try store.conversation(id: conversation.id), conversation)
    }

    func testUnknownIdReturnsNil() throws {
        XCTAssertNil(try store.conversation(id: UUID()))
    }

    func testSavingAgainUpdatesWithoutTouchingChildren() throws {
        var conversation = makeConversation()
        try store.save(conversation)
        try store.saveParticipants([Participant(conversationId: conversation.id, name: "A")])

        conversation.title = "Renamed"
        conversation.state = .approved
        try store.save(conversation)

        XCTAssertEqual(try store.conversation(id: conversation.id)?.title, "Renamed")
        XCTAssertEqual(try store.participants(conversationId: conversation.id).count, 1)
        XCTAssertEqual(try store.listConversations().count, 1)
    }

    func testListIsNewestFirstWithCounts() throws {
        let older = makeConversation(title: "Older", startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let newer = makeConversation(title: "Newer", startedAt: Date(timeIntervalSince1970: 1_800_100_000))
        try store.save(older)
        try store.save(newer)

        let user = Participant(conversationId: newer.id, name: "Thijs", isUser: true)
        let other = Participant(conversationId: newer.id, name: "Anna")
        try store.saveParticipants([other, user])

        let oldVersion = TranscriptVersion(conversationId: newer.id, engine: "old")
        try store.saveTranscript(version: oldVersion, segments: [
            Segment(transcriptVersionId: oldVersion.id, startMs: 0, endMs: 1, text: "oud"),
        ])
        let version = TranscriptVersion(conversationId: newer.id, engine: "new")
        try store.saveTranscript(version: version, segments: [
            Segment(transcriptVersionId: version.id, startMs: 0, endMs: 1, text: "een"),
            Segment(transcriptVersionId: version.id, startMs: 1, endMs: 2, text: "twee"),
        ])
        try database.queue.write { db in
            try Outcome(conversationId: newer.id, kind: .myAction, text: "a", status: .proposed, source: .model).insert(db)
            try Outcome(conversationId: newer.id, kind: .decision, text: "b", status: .approved, source: .user).insert(db)
            try Outcome(conversationId: newer.id, kind: .decision, text: "c", status: .approved, source: .user).insert(db)
            try Outcome(conversationId: newer.id, kind: .information, text: "d", status: .rejected, source: .model).insert(db)
        }

        let list = try store.listConversations()
        XCTAssertEqual(list.map(\.conversation.title), ["Newer", "Older"])
        XCTAssertEqual(list[0].participantNames, ["Thijs", "Anna"])
        XCTAssertEqual(list[0].segmentCount, 2)
        XCTAssertEqual(list[0].proposedOutcomes, 1)
        XCTAssertEqual(list[0].approvedOutcomes, 2)
        XCTAssertEqual(list[1].participantNames, [])
        XCTAssertEqual(list[1].segmentCount, 0)
    }

    func testSavingATranscriptMakesItCurrentAndKeepsTheOldOne() throws {
        let conversation = makeConversation()
        try store.save(conversation)
        let first = TranscriptVersion(conversationId: conversation.id, engine: "first")
        try store.saveTranscript(version: first, segments: [
            Segment(transcriptVersionId: first.id, startMs: 0, endMs: 1, text: "eerste"),
        ])
        let second = TranscriptVersion(conversationId: conversation.id, engine: "second")
        try store.saveTranscript(version: second, segments: [
            Segment(transcriptVersionId: second.id, startMs: 5, endMs: 6, text: "later"),
            Segment(transcriptVersionId: second.id, startMs: 0, endMs: 1, text: "eerder"),
        ])

        XCTAssertEqual(try store.currentTranscriptVersion(conversationId: conversation.id)?.engine, "second")
        XCTAssertEqual(try store.currentSegments(conversationId: conversation.id).map(\.text), ["eerder", "later"])
        let versions = try database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcriptVersion")
        }
        XCTAssertEqual(versions, 2)
    }

    func testTracksRoundTrip() throws {
        let conversation = makeConversation()
        try store.save(conversation)
        let tracks = [
            Track(conversationId: conversation.id, kind: .microphone, relativePath: "c/mic.caf"),
            Track(conversationId: conversation.id, kind: .system, relativePath: "c/sys.caf"),
        ]
        try store.saveTracks(tracks)
        XCTAssertEqual(try store.tracks(conversationId: conversation.id), tracks)
    }
}
