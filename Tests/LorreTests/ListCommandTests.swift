import LorreCore
import XCTest
@testable import Lorre

final class ListCommandTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func summary(title: String, duration: Double?) -> ConversationSummary {
        ConversationSummary(
            conversation: Conversation(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                title: title,
                type: .network,
                state: .proposed,
                startedAt: Date(timeIntervalSince1970: 1_791_453_600), // 2026-10-08 10:00 UTC
                durationSeconds: duration
            ),
            participantNames: ["Thijs", "Anna"],
            segmentCount: 382,
            proposedOutcomes: 3,
            approvedOutcomes: 1
        )
    }

    func testEmptyList() throws {
        XCTAssertEqual(try ListCommand.render([], json: false), "No conversations.")
        XCTAssertEqual(try ListCommand.render([], json: true).filter { !$0.isWhitespace }, "[]")
    }

    func testTableLine() throws {
        let output = try ListCommand.render([summary(title: "Call met Anna", duration: 1741.27)], json: false, timeZone: utc)
        XCTAssertEqual(output, "2026-10-08 10:00   29 min  proposed       382 seg  Call met Anna")
    }

    func testTableWithoutDuration() throws {
        let output = try ListCommand.render([summary(title: "x", duration: nil)], json: false, timeZone: utc)
        XCTAssertTrue(output.contains("        -  proposed"), output)
    }

    func testJSONCarriesTheFieldsAnAgentNeeds() throws {
        let output = try ListCommand.render([summary(title: "Call met Anna", duration: 60)], json: true)
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["id"] as? String, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(rows[0]["title"] as? String, "Call met Anna")
        XCTAssertEqual(rows[0]["type"] as? String, "network")
        XCTAssertEqual(rows[0]["state"] as? String, "proposed")
        XCTAssertEqual(rows[0]["startedAt"] as? String, "2026-10-08T10:00:00Z")
        XCTAssertEqual(rows[0]["participants"] as? [String], ["Thijs", "Anna"])
        XCTAssertEqual(rows[0]["segmentCount"] as? Int, 382)
        XCTAssertEqual(rows[0]["proposedOutcomes"] as? Int, 3)
        XCTAssertEqual(rows[0]["approvedOutcomes"] as? Int, 1)
    }

    func testImportReportListsSkippedFolders() {
        var report = LegacyImportReport()
        report.imported = [UUID(), UUID()]
        report.alreadyPresent = [UUID()]
        report.skipped = [.init(folder: "abc", reason: "no session.json")]
        XCTAssertEqual(
            ImportLegacyCommand.render(report),
            "Imported 2, already present 1, skipped 1\n  skipped abc: no session.json"
        )
    }
}
