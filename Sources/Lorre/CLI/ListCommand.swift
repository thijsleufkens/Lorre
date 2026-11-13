import ArgumentParser
import Foundation
import LorreCore

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the conversations in the database, newest first."
    )

    @OptionGroup var store: StoreOptions

    @Flag(help: "Print JSON instead of a table.")
    var json: Bool = false

    func run() throws {
        let summaries = try ConversationStore(database: store.openDatabase()).listConversations()
        print(try Self.render(summaries, json: json))
    }

    static func render(
        _ summaries: [ConversationSummary],
        json: Bool,
        timeZone: TimeZone = .current
    ) throws -> String {
        json ? try renderJSON(summaries) : renderTable(summaries, timeZone: timeZone)
    }

    private static func renderTable(_ summaries: [ConversationSummary], timeZone: TimeZone) -> String {
        guard !summaries.isEmpty else { return "No conversations." }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return summaries.map { summary in
            let conversation = summary.conversation
            let minutes = conversation.durationSeconds.map { "\(Int(($0 / 60).rounded())) min" } ?? "-"
            return [
                formatter.string(from: conversation.startedAt),
                minutes.leftPadded(to: 7),
                conversation.state.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0),
                "\(summary.segmentCount)".leftPadded(to: 5) + " seg",
                conversation.title,
            ].joined(separator: "  ")
        }.joined(separator: "\n")
    }

    private struct Row: Encodable {
        var id: String
        var title: String
        var type: String
        var state: String
        var startedAt: Date
        var durationSeconds: Double?
        var participants: [String]
        var segmentCount: Int
        var proposedOutcomes: Int
        var approvedOutcomes: Int
    }

    private static func renderJSON(_ summaries: [ConversationSummary]) throws -> String {
        let rows = summaries.map { summary in
            Row(
                id: summary.conversation.id.uuidString,
                title: summary.conversation.title,
                type: summary.conversation.type.rawValue,
                state: summary.conversation.state.rawValue,
                startedAt: summary.conversation.startedAt,
                durationSeconds: summary.conversation.durationSeconds,
                participants: summary.participantNames,
                segmentCount: summary.segmentCount,
                proposedOutcomes: summary.proposedOutcomes,
                approvedOutcomes: summary.approvedOutcomes
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(rows), as: UTF8.self)
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: " ", count: length - count) + self
    }
}
