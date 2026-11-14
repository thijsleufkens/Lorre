import ArgumentParser
import Foundation
import LorreCore

struct MCPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Run the MCP server on stdin/stdout, for agents. Stops when stdin closes."
    )

    @OptionGroup var store: StoreOptions

    func run() throws {
        let server = MCPServer(database: try store.openDatabase())
        FileHandle.standardError.write(Data("Lorre MCP server ready.\n".utf8))
        // Only protocol messages go to stdout; diagnostics go to stderr.
        while let line = readLine(strippingNewline: true) {
            guard let reply = server.handle(line: line) else { continue }
            FileHandle.standardOutput.write(Data((reply + "\n").utf8))
        }
    }
}
