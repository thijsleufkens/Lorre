import ArgumentParser
import Foundation
import LorreCore

struct ImportLegacyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-legacy",
        abstract: "Copy the sessions of the old file store into the conversation database.",
        discussion: "The old sessions are only read. Running the import again adds new sessions and leaves the rest alone."
    )

    @OptionGroup var store: StoreOptions

    func run() throws {
        let report = try LegacySessionImporter(paths: store.paths, database: store.openDatabase()).run()
        print(Self.render(report))
    }

    static func render(_ report: LegacyImportReport) -> String {
        var lines = [
            "Imported \(report.imported.count), already present \(report.alreadyPresent.count), skipped \(report.skipped.count)",
        ]
        lines += report.skipped.map { "  skipped \($0.folder): \($0.reason)" }
        return lines.joined(separator: "\n")
    }
}
