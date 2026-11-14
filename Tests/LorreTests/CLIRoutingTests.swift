import XCTest
@testable import Lorre

final class CLIRoutingTests: XCTestCase {
    func testNoArgumentsLaunchesGUI() {
        XCTAssertFalse(CLIRouting.isCLIInvocation(["/Applications/Lorre.app/Contents/MacOS/Lorre"]))
    }

    func testTranscribeSubcommandIsCLI() {
        XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", "transcribe", "clip.m4a"]))
    }

    func testStoreSubcommandsAreCLI() {
        XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", "list"]))
        XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", "list", "--json"]))
        XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", "import-legacy"]))
    }

    func testEveryRegisteredSubcommandIsRouted() {
        // A command that is registered but not routed would silently open the GUI.
        for command in LorreCLI.configuration.subcommands {
            let name = command.configuration.commandName ?? ""
            XCTAssertTrue(CLIRouting.subcommands.contains(name), "\(name) is not routed to the CLI")
        }
    }

    func testLaunchServicesArgumentLaunchesGUI() {
        // macOS LaunchServices can pass process-serial-number style args; must still be GUI.
        XCTAssertFalse(CLIRouting.isCLIInvocation(["/path/Lorre", "-psn_0_123456"]))
        XCTAssertFalse(CLIRouting.isCLIInvocation(["/path/Lorre", "-NSDocumentRevisionsDebugMode", "YES"]))
    }

    func testHelpFlagRoutesCLI() {
        XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", "--help"]))
        XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", "-h"]))
    }

    func testHelpSubcommandRoutesCLI() {
        // ArgumentParser's own --help output advertises `Lorre help <subcommand>`;
        // that invocation must reach the CLI, not launch the GUI.
        XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", "help"]))
        XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", "help", "transcribe"]))
    }
}
