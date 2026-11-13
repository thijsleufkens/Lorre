import ArgumentParser
import Foundation
import LorreCapture
import LorreCore

struct RecoverCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recover",
        abstract: "Find recordings that were interrupted and turn them back into conversations.",
        discussion: "The app does this by itself at launch. Audio is never changed or removed."
    )

    @OptionGroup var store: StoreOptions

    func run() throws {
        let report = try RecordingRecovery(paths: store.paths, database: store.openDatabase()).run()
        print(Self.render(report))
    }

    static func render(_ report: RecoveryReport) -> String {
        var lines = [
            "Recovered \(report.recovered.count + report.adopted.count) interrupted recording(s), "
                + "\(report.requeue.count) waiting to be transcribed, \(report.stillLive.count) being recorded now",
        ]
        lines += (report.recovered + report.adopted).map { "  recovered \($0.uuidString)" }
        lines += report.requeue.map { "  waiting   \($0.uuidString)" }
        return lines.joined(separator: "\n")
    }
}
