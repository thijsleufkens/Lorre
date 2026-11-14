import ArgumentParser
import Foundation
import LorreCore

/// Options shared by the commands that work on the conversation database.
struct StoreOptions: ParsableArguments {
    @Option(help: ArgumentHelp(
        "Use this folder instead of ~/Library/Application Support/Lorre.",
        valueName: "path"
    ))
    var root: String?

    var paths: LorrePaths {
        guard let root else { return LorrePaths() }
        return LorrePaths(root: URL(fileURLWithPath: root, isDirectory: true))
    }

    func openDatabase() throws -> LorreDatabase {
        try LorreDatabase(url: paths.database)
    }
}
