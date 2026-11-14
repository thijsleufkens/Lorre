import ArgumentParser
import Foundation
import LorreCore

struct EvalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eval",
        abstract: "Score the proposals for a conversation against a hand-made reference. Writes nothing."
    )

    @Argument(help: "Path of the reference JSON file (format: docs/eval.md).")
    var reference: String

    @OptionGroup var proposer: ProposerOptions
    @OptionGroup var store: StoreOptions

    @Flag(help: "Print JSON instead of text.")
    var json: Bool = false

    func run() async throws {
        let language = try proposer.resolvedLanguage()
        let referenceData: Data
        do {
            referenceData = try Data(contentsOf: URL(fileURLWithPath: (reference as NSString).expandingTildeInPath))
        } catch {
            throw ValidationError("Cannot read the reference file: \(reference).")
        }
        let parsed: EvalReference
        do {
            parsed = try EvalReference.load(from: referenceData)
        } catch let error as EvalReference.ValidationError {
            throw ValidationError(error.localizedDescription)
        } catch {
            throw ValidationError("The reference file is not valid: \(error.localizedDescription)")
        }

        let conversations = ConversationStore(database: try store.openDatabase())
        let conversation = try ShowCommand.resolve(parsed.conversationId, in: conversations.listConversations().map(\.conversation))
        let participants = try conversations.activeParticipants(conversationId: conversation.id)
        let segments = try conversations.currentSegments(conversationId: conversation.id)
        guard !segments.isEmpty else { throw ValidationError("This conversation has no transcript yet.") }

        let engine = proposer.makeProposer()
        let started = Date()
        let proposals: [ProposedOutcome]
        do {
            proposals = try await engine.propose(ProposalInput(
                type: conversation.type, language: language, participants: participants, segments: segments
            ))
        } catch let error as OllamaError {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            throw ExitCode.failure
        }
        let elapsed = Date().timeIntervalSince(started)
        let report = ProposalEvaluator.score(reference: parsed, proposals: proposals, participants: participants)
        print(try Self.render(report, model: engine.identifier, elapsedSeconds: elapsed, json: json))
    }

    static func render(_ report: EvalReport, model: String, elapsedSeconds: Double, json: Bool) throws -> String {
        if json {
            struct Output: Encodable {
                var model: String
                var items: [EvalItemResult]
                var recallFound: Double
                var recallCorrect: Double
                var proposals: Int
                var unmatchedProposals: Int
                var elapsedSeconds: Double
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let output = Output(
                model: model, items: report.items, recallFound: report.recallFound,
                recallCorrect: report.recallCorrect, proposals: report.proposalCount,
                unmatchedProposals: report.unmatchedProposalCount, elapsedSeconds: elapsedSeconds
            )
            return String(decoding: try encoder.encode(output), as: UTF8.self)
        }
        var lines = ["Model: \(model)", ""]
        for item in report.items {
            let status = item.correct ? "correct" : (item.found ? "found, wrong kind or owner" : "MISSED")
            lines.append("  \(status.padding(toLength: 26, withPad: " ", startingAt: 0)) \(item.kind): \(item.label)")
        }
        lines.append("")
        lines.append("Recall (found):   \(report.foundCount)/\(report.items.count)  \(percent(report.recallFound))")
        lines.append("Recall (correct): \(report.correctCount)/\(report.items.count)  \(percent(report.recallCorrect))")
        lines.append("Proposals: \(report.proposalCount), matching no expected item: \(report.unmatchedProposalCount)")
        lines.append("Elapsed: \(String(format: "%.1f", elapsedSeconds)) s")
        return lines.joined(separator: "\n")
    }

    private static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}
