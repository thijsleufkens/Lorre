import XCTest
@testable import LorreCore

final class SearchStoreTests: XCTestCase {
    private var database: LorreDatabase!
    private var store: ConversationStore!
    private var search: SearchStore!
    private var first: Conversation!
    private var second: Conversation!

    override func setUpWithError() throws {
        database = try LorreDatabase.inMemory()
        store = ConversationStore(database: database)
        search = SearchStore(database: database)
        first = makeConversation(title: "Fotograaf", startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        second = makeConversation(title: "Marge", startedAt: Date(timeIntervalSince1970: 1_800_100_000))
        try store.save(first)
        try store.save(second)
        let a = TranscriptVersion(conversationId: first.id, engine: "t")
        try store.saveTranscript(version: a, segments: [
            Segment(transcriptVersionId: a.id, startMs: 1000, endMs: 2000, text: "Ik wil richting de maakindustrie"),
            Segment(transcriptVersionId: a.id, startMs: 3000, endMs: 4000, text: "Dat is een café in Weert"),
        ])
        let b = TranscriptVersion(conversationId: second.id, engine: "t")
        try store.saveTranscript(version: b, segments: [
            Segment(transcriptVersionId: b.id, startMs: 500, endMs: 900, text: "De marge per productgroep klopt niet"),
        ])
    }

    func testFindsTheMatchingConversationAndSegment() throws {
        let hits = try search.search("productgroep")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].conversationId, second.id)
        XCTAssertEqual(hits[0].conversationTitle, "Marge")
        XCTAssertEqual(hits[0].startMs, 500)
        XCTAssertTrue(hits[0].snippet.contains("[productgroep]"), hits[0].snippet)
    }

    func testPrefixMatchesLongerWord() throws {
        XCTAssertEqual(try search.search("maak").map(\.conversationId), [first.id])
    }

    func testAllWordsMustMatch() throws {
        XCTAssertEqual(try search.search("marge maakindustrie").count, 0)
        XCTAssertEqual(try search.search("marge klopt").count, 1)
    }

    func testIgnoresCaseAndDiacritics() throws {
        XCTAssertEqual(try search.search("CAFE").map(\.startMs), [3000])
    }

    func testEmptyOrPunctuationQueryReturnsNothing() throws {
        XCTAssertEqual(try search.search("").count, 0)
        XCTAssertEqual(try search.search("  \"*( ").count, 0)
    }

    func testQuerySyntaxCannotBreakTheSearch() throws {
        XCTAssertNoThrow(try search.search("marge AND (NOT \"x"))
    }

    func testOnlyTheCurrentTranscriptIsSearched() throws {
        let replacement = TranscriptVersion(conversationId: second.id, engine: "t2")
        try store.saveTranscript(version: replacement, segments: [
            Segment(transcriptVersionId: replacement.id, startMs: 0, endMs: 1, text: "Opnieuw getranscribeerd"),
        ])
        XCTAssertEqual(try search.search("productgroep").count, 0)
        XCTAssertEqual(try search.search("opnieuw").count, 1)
    }

    func testEditedTextIsSearchable() throws {
        try database.queue.write { db in
            try db.execute(sql: "UPDATE segment SET text = 'Koffiebonen opgestuurd' WHERE startMs = 500")
        }
        XCTAssertEqual(try search.search("koffiebonen").count, 1)
        XCTAssertEqual(try search.search("productgroep").count, 0)
    }
}
