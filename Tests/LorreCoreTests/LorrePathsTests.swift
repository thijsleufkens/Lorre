import XCTest
@testable import LorreCore

final class LorrePathsTests: XCTestCase {
    func testDerivedLocationsSitUnderTheRoot() {
        let paths = LorrePaths(root: URL(fileURLWithPath: "/tmp/lorre-root", isDirectory: true))
        XCTAssertEqual(paths.database.path, "/tmp/lorre-root/lorre.sqlite")
        XCTAssertEqual(paths.conversations.path, "/tmp/lorre-root/conversations")
        XCTAssertEqual(paths.legacySessions.path, "/tmp/lorre-root/sessions")
    }

    func testDefaultRootIsTheLorreApplicationSupportFolder() {
        XCTAssertEqual(LorrePaths.defaultRoot().lastPathComponent, "Lorre")
    }
}
