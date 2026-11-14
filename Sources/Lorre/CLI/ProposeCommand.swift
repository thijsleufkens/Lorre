import ArgumentParser
import Foundation
import LorreCore

/// Options shared by the commands that run an outcome proposer.
struct ProposerOptions: ParsableArguments {
    static let defaultModel = "gemma4:e4b"

    @Option(help: "The Ollama model that proposes the outcomes.")
    var model: String = ProposerOptions.defaultModel

    @Option(help: ArgumentHelp("The language of the conversation: nl or en. Default: your system language.", valueName: "nl|en"))
    var language: String?

    func resolvedLanguage() throws -> LorreLanguage {
        guard let language else { return .current }
        guard let value = LorreLanguage(rawValue: language.lowercased()) else {
            throw ValidationError("--language must be nl or en.")
        }
        return value
    }

    func makeProposer() -> any OutcomeProposer {
        TwoStepOutcomeProposer(generator: OllamaTextGenerator(model: model))
    }
}

struct ProposeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "propose",
        abstract: "Let a local model propose the outcomes of a conversation, for you to review."
    )

    @Argument(help: "Conversation id, or the first characters of it (see `list --json`).")
    var id: String

    @OptionGroup var proposer: ProposerOptions
    @OptionGroup var store: StoreOptions

    @Flag(name: .customLong("dry-run"), help: "Print the proposals without storing them.")
    var dryRun: Bool = false

    func run() async throws {
        let language = try proposer.resolvedLanguage()
        let database = try store.openDatabase()
        let conversations = ConversationStore(database: database)
        let conversation = try ShowCommand.resolve(id, in: conversations.listConversations().map(\.conversation))
        let participants = try conversations.activeParticipants(conversationId: conversation.id)
        let segments = try conversations.currentSegments(conversationId: conversation.id)
        guard !segments.isEmpty else {
            throw ValidationError("This conversation has no transcript yet.")
        }

        let engine = proposer.makeProposer()
        let proposals: [ProposedOutcome]
        do {
            proposals = try await engine.propose(ProposalInput(
                type: conversation.type, language: language, participants: participants, segments: segments
            ))
        } catch let error as OllamaError {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            throw ExitCode.failure
        }

        print(Self.render(proposals, participants: participants, segments: segments, language: language))
        guard !dryRun else {
            print("\nDry run: nothing was stored.")
            return
        }
        let stored = try ReviewStore(database: database).replaceProposals(
            conversationId: conversation.id, proposals: proposals, modelIdentifier: engine.identifier
        )
        print("\nStored \(stored.count) proposal\(stored.count == 1 ? "" : "s") (\(engine.identifier)).")
    }

    /// Proposals grouped by kind, each with its owner and the time of its evidence.
    static func render(
        _ proposals: [ProposedOutcome],
        participants: [Participant],
        segments: [Segment],
        language: LorreLanguage
    ) -> String {
        guard !proposals.isEmpty else { return "No proposals." }
        let names = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0.name) })
        let segmentsById = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        var blocks: [String] = []
        for kind in OutcomeKind.displayOrder {
            let group = proposals.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            var lines = ["\(kind.title(language)) (\(group.count))"]
            for proposal in group {
                var detail: [String] = []
                if let owner = proposal.ownerParticipantId.flatMap({ names[$0] }) { detail.append(owner) }
                let starts = proposal.evidenceSegmentIds.compactMap { segmentsById[$0]?.startMs }
                if let start = starts.min() { detail.append(Self.stamp(start)) }
                let suffix = detail.isEmpty ? "" : "  [\(detail.joined(separator: ", "))]"
                lines.append("  - \(proposal.text)\(suffix)")
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    static func stamp(_ ms: Int) -> String {
        let seconds = ms / 1000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
