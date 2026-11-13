import ArgumentParser
import Foundation
import LorreCapture

/// Internal: lets a test kill a process that is in the middle of writing audio.
struct CaptureSelfTestCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture-selftest",
        abstract: "Write a test tone without closing the file (used by the test suite).",
        shouldDisplay: false
    )

    @Option(help: "File to write.")
    var out: String

    @Option(help: "Seconds of audio to write before idling.")
    var seconds: Double = 60

    func run() throws {
        try WriterSelfTest.run(output: URL(fileURLWithPath: out), seconds: seconds)
    }
}
