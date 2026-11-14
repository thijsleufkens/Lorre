import LorreCore
import XCTest
@testable import Lorre

final class RecordsCommandTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func listing(version: Int = 1, status: RecordStatus = .approved, title: String = "Call met Anna") -> RecordListing {
        RecordListing(
            recordId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            recordVersion: version, status: status, title: title, type: .network,
            startedAt: Date(timeIntervalSince1970: 1_791_453_600), // 2026-10-08 10:00 UTC
            approvedAt: nil, path: "/tmp/x.json"
        )
    }

    func testEmptyListing() throws {
        XCTAssertEqual(try RecordsCommand.render([], json: false), "No records.")
        XCTAssertEqual(try RecordsCommand.render([], json: true).filter { !$0.isWhitespace }, "[]")
    }

    func testTableLine() throws {
        let output = try RecordsCommand.render([listing(), listing(version: 0, status: .draft, title: "Concept")], json: false, timeZone: utc)
        XCTAssertEqual(output, """
            11111111  2026-10-08 10:00  approved  v1   Call met Anna
            11111111  2026-10-08 10:00  draft     v0   Concept
            """)
    }

    func testJSONListing() throws {
        let output = try RecordsCommand.render([listing()], json: true)
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["recordId"] as? String, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(rows[0]["status"] as? String, "approved")
        XCTAssertEqual(rows[0]["recordVersion"] as? Int, 1)
        XCTAssertEqual(rows[0]["path"] as? String, "/tmp/x.json")
        XCTAssertEqual(rows[0]["startedAt"] as? String, "2026-10-08T10:00:00Z")
    }

    func testRecordRendersJSONAndMarkdown() throws {
        let records = try ExportedRecords()
        let conversation = try records.add(title: "Call met Anna", startedAt: 1_791_453_600, approved: true)
        let record = try RecordCatalog(database: records.database).record(conversation.id)

        let json = try RecordCommand.render(record, markdown: false)
        XCTAssertEqual(try MeetingRecord.decoder().decode(MeetingRecord.self, from: Data(json.utf8)), record)

        let markdown = try RecordCommand.render(record, markdown: true, language: .english)
        XCTAssertTrue(markdown.hasPrefix("# Call met Anna"))
        XCTAssertTrue(markdown.contains("We doen het"))
        XCTAssertTrue(markdown.contains("**Anna** (01:05): Dan geef ik je naam door."))
    }

    func testMarkProcessedMessage() {
        let cursor = ConsumerCursor(
            consumerName: "agent", conversationId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, recordVersion: 2
        )
        XCTAssertEqual(
            MarkProcessedCommand.render(cursor, title: "Call"),
            "Marked \"Call\" (11111111) version 2 as processed by agent."
        )
    }

    func testNewNeedsAConsumer() throws {
        XCTAssertThrowsError(try RecordsCommand.parse(["--new"]))
        XCTAssertNoThrow(try RecordsCommand.parse(["--new", "--consumer", "agent"]))
        XCTAssertNoThrow(try RecordsCommand.parse(["--status", "draft", "--json"]))
        XCTAssertThrowsError(try RecordsCommand.parse(["--status", "bogus"]))
    }

    func testCommandsAreRouted() {
        for name in ["records", "record", "mark-processed", "mcp"] {
            XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", name]), name)
        }
    }
}
