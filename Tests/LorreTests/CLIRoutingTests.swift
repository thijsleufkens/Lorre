import XCTest
@testable import Lorre

final class CLIRoutingTests: XCTestCase {
    func testNoArgumentsLaunchesGUI() {
        XCTAssertFalse(CLIRouting.isCLIInvocation(["/Applications/Lorre.app/Contents/MacOS/Lorre"]))
    }

    func testTranscribeSubcommandIsCLI() {
        XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", "transcribe", "clip.m4a"]))
    }

    func testLaunchServicesArgumentLaunchesGUI() {
        // macOS LaunchServices can pass process-serial-number style args; must still be GUI.
        XCTAssertFalse(CLIRouting.isCLIInvocation(["/path/Lorre", "-psn_0_123456"]))
        XCTAssertFalse(CLIRouting.isCLIInvocation(["/path/Lorre", "-NSDocumentRevisionsDebugMode", "YES"]))
    }
}
