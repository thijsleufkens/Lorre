import ArgumentParser

struct LorreCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "Lorre",
        abstract: "Lorre local transcription CLI.",
        subcommands: [
            TranscribeCommand.self, ListCommand.self, ShowCommand.self, ProcessCommand.self,
            RecoverCommand.self, ImportLegacyCommand.self, CaptureSelfTestCommand.self,
            RecordsCommand.self, RecordCommand.self, MarkProcessedCommand.self, MCPCommand.self,
            ProposeCommand.self, EvalCommand.self, EvalSpeechCommand.self,
        ]
    )
}
