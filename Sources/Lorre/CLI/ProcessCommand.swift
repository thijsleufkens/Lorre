import ArgumentParser
import Foundation
import LorreCore

struct ProcessCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "process",
        abstract: "Transcribe a recorded conversation (again), for example an interrupted recording."
    )

    @Argument(help: "Conversation id, or the first characters of it.")
    var id: String

    @OptionGroup var store: StoreOptions

    @Flag(help: "Do not write the automatic export, even when it is enabled in the settings.")
    var noExport: Bool = false

    @Flag(help: "Suppress progress output on stderr.")
    var quiet: Bool = false

    func run() async throws {
        let database = try store.openDatabase()
        let conversations = ConversationStore(database: database)
        let conversation = try ShowCommand.resolve(id, in: conversations.listConversations().map(\.conversation))
        guard conversation.state != .recording else {
            throw ValidationError("This conversation is still being recorded.")
        }

        let factory = TranscribeServiceFactory()
        let settings = try await factory.settings.load()
        await factory.diarization.setDiarizationEngine(settings.diarizationEngine)
        let processor = ConversationProcessor(
            paths: store.paths,
            database: database,
            transcription: factory.transcription,
            diarization: factory.diarization
        )
        var options = ConversationProcessor.Options(settings: settings)
        if noExport { options.automaticExport = nil }
        let processed = try await processor.process(
            conversation.id,
            options: options,
            onProgress: { [quiet] update in
                guard !quiet else { return }
                FileHandle.standardError.write(Data("[\(Int((update.fraction ?? 0) * 100))%] \(update.label)\n".utf8))
            }
        )
        let segments = try conversations.currentSegments(conversationId: processed.id).count
        print("\(processed.title): \(processed.state.rawValue), \(segments) segments")
    }
}
