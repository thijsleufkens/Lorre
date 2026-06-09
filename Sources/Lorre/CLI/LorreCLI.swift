import ArgumentParser

struct LorreCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "Lorre",
        abstract: "Lorre local transcription CLI.",
        subcommands: [TranscribeCommand.self]
    )
}
