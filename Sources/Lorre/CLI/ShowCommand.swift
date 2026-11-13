import ArgumentParser
import Foundation
import LorreCore

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Print the transcript of a conversation."
    )

    @Argument(help: "Conversation id, or the first characters of it (see `list --json`).")
    var id: String

    @OptionGroup var store: StoreOptions

    @Flag(help: "Print JSON instead of text.")
    var json: Bool = false

    func run() throws {
        let conversations = ConversationStore(database: try store.openDatabase())
        let conversation = try Self.resolve(id, in: conversations.listConversations().map(\.conversation))
        print(try Self.render(
            conversation: conversation,
            participants: conversations.participants(conversationId: conversation.id),
            segments: conversations.currentSegments(conversationId: conversation.id),
            json: json
        ))
    }

    /// Finds the conversation whose id starts with the given text.
    static func resolve(_ text: String, in conversations: [Conversation]) throws -> Conversation {
        let needle = text.uppercased()
        let matches = conversations.filter { $0.id.uuidString.hasPrefix(needle) }
        switch matches.count {
        case 1: return matches[0]
        case 0: throw ValidationError("No conversation with an id starting with \(text).")
        default: throw ValidationError("\(matches.count) conversations start with \(text); give more characters.")
        }
    }

    static func render(
        conversation: Conversation,
        participants: [Participant],
        segments: [Segment],
        json: Bool
    ) throws -> String {
        let names = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0.name) })
        if json {
            struct Line: Encodable {
                var startMs: Int
                var endMs: Int
                var speaker: String?
                var text: String
            }
            struct Output: Encodable {
                var id: String
                var title: String
                var state: String
                var startedAt: Date
                var durationSeconds: Double?
                var lastError: String?
                var segments: [Line]
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let output = Output(
                id: conversation.id.uuidString,
                title: conversation.title,
                state: conversation.state.rawValue,
                startedAt: conversation.startedAt,
                durationSeconds: conversation.durationSeconds,
                lastError: conversation.lastError,
                segments: segments.map {
                    Line(startMs: $0.startMs, endMs: $0.endMs, speaker: $0.participantId.flatMap { names[$0] }, text: $0.text)
                }
            )
            return String(decoding: try encoder.encode(output), as: UTF8.self)
        }

        var lines = ["\(conversation.title)  (\(conversation.state.rawValue))"]
        if let error = conversation.lastError { lines.append("Note: \(error)") }
        if segments.isEmpty { lines.append("No transcript yet.") }
        lines += segments.map { segment in
            let seconds = segment.startMs / 1000
            let stamp = String(format: "%02d:%02d", seconds / 60, seconds % 60)
            let speaker = segment.participantId.flatMap { names[$0] } ?? "?"
            return "[\(stamp)] \(speaker): \(segment.text)"
        }
        return lines.joined(separator: "\n")
    }
}
