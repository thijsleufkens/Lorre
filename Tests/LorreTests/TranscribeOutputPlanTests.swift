import Foundation
import XCTest
@testable import Lorre

final class TranscribeOutputPlanTests: XCTestCase {
    func testMarkdownToStdoutWhenNoOut() throws {
        XCTAssertEqual(try TranscribeOutputPlan.resolve(format: .md, out: nil), .stdout(.markdown))
    }

    func testJSONToStdoutWhenNoOut() throws {
        XCTAssertEqual(try TranscribeOutputPlan.resolve(format: .json, out: nil), .stdout(.json))
    }

    func testSingleFileWhenOutGiven() throws {
        let plan = try TranscribeOutputPlan.resolve(format: .md, out: "/tmp/x.md")
        XCTAssertEqual(plan, .file(URL(fileURLWithPath: "/tmp/x.md"), .markdown))
    }

    func testBothRequiresOut() {
        XCTAssertThrowsError(try TranscribeOutputPlan.resolve(format: .both, out: nil))
    }

    func testBothProducesMarkdownAndJSONPair() throws {
        let plan = try TranscribeOutputPlan.resolve(format: .both, out: "/tmp/walkthrough")
        XCTAssertEqual(plan, .pair(
            markdown: URL(fileURLWithPath: "/tmp/walkthrough.md"),
            json: URL(fileURLWithPath: "/tmp/walkthrough.json")
        ))
    }
}
