import Foundation
import LorreCore

/// A minimal Model Context Protocol server: newline-delimited JSON-RPC 2.0, one message per line.
/// Pure: `handle(line:)` turns one incoming line into the line to send back, or nil for no reply.
struct MCPServer {
    static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    static let serverVersion = "1.0.0"

    private let catalog: RecordCatalog
    private let consumers: ConsumerStore
    private let now: @Sendable () -> Date

    init(database: LorreDatabase, now: @escaping @Sendable () -> Date = { Date() }) {
        catalog = RecordCatalog(database: database)
        consumers = ConsumerStore(database: database)
        self.now = now
    }

    // MARK: Protocol

    func handle(line: String) -> String? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let data = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data)
        else {
            return Self.encode(error: -32700, message: "Parse error", id: NSNull())
        }
        guard let message = parsed as? [String: Any], let method = message["method"] as? String else {
            return Self.encode(error: -32600, message: "Invalid request", id: message(from: parsed)["id"] ?? NSNull())
        }
        // No id: a notification. It never gets a response, not even for an unknown method.
        guard let id = message["id"], !(id is NSNull) else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
                ?? Self.supportedProtocolVersions[0]
            return Self.encode(result: [
                "protocolVersion": version,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "lorre", "version": Self.serverVersion],
            ], id: id)
        case "ping":
            return Self.encode(result: [String: Any](), id: id)
        case "tools/list":
            return Self.encode(result: ["tools": Self.tools], id: id)
        case "tools/call":
            guard let name = params["name"] as? String else {
                return Self.encode(error: -32602, message: "Missing tool name", id: id)
            }
            guard Self.tools.contains(where: { $0["name"] as? String == name }) else {
                return Self.encode(error: -32602, message: "Unknown tool: \(name)", id: id)
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                return Self.encode(result: Self.toolResult(try call(name, arguments), isError: false), id: id)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return Self.encode(result: Self.toolResult(message, isError: true), id: id)
            }
        default:
            return Self.encode(error: -32601, message: "Method not found: \(method)", id: id)
        }
    }

    private func message(from parsed: Any) -> [String: Any] { parsed as? [String: Any] ?? [:] }

    // MARK: Tools

    private struct ToolError: LocalizedError {
        var errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    private static var tools: [[String: Any]] { [
        [
            "name": "list_records",
            "description": "List the exported meeting records, newest conversation first. Each entry is the latest version of one record.",
            "inputSchema": schema([
                "consumer": ["type": "string", "description": "Your name as a consumer; needed with onlyNew."],
                "onlyNew": ["type": "boolean", "description": "Leave out records this consumer already marked as processed at their current version."],
                "status": ["type": "string", "enum": ["draft", "approved"], "description": "Only records with this status."],
            ]),
        ],
        [
            "name": "get_record",
            "description": "The full record as JSON: conversation, approved outcomes and transcript.",
            "inputSchema": schema(["recordId": ["type": "string", "description": "A record id or an unambiguous prefix of it."]], required: ["recordId"]),
        ],
        [
            "name": "mark_processed",
            "description": "Mark a record version as processed by a consumer, so list_records with onlyNew no longer returns it.",
            "inputSchema": schema([
                "recordId": ["type": "string", "description": "A record id or an unambiguous prefix of it."],
                "consumer": ["type": "string", "description": "Your name as a consumer."],
                "version": ["type": "integer", "description": "The record version; default is the latest."],
            ], required: ["recordId", "consumer"]),
        ],
        [
            "name": "get_transcript",
            "description": "The transcript of a record as plain text, one line per segment with time and speaker.",
            "inputSchema": schema(["recordId": ["type": "string", "description": "A record id or an unambiguous prefix of it."]], required: ["recordId"]),
        ],
    ] }

    private static func schema(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }

    private func call(_ name: String, _ arguments: [String: Any]) throws -> String {
        switch name {
        case "list_records":
            let status = try arguments["status"].map { value -> RecordStatus in
                guard let text = value as? String, let status = RecordStatus(rawValue: text) else {
                    throw ToolError("status must be \"draft\" or \"approved\".")
                }
                return status
            }
            let onlyNew = (arguments["onlyNew"] as? Bool) ?? false
            let consumer = (arguments["consumer"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if onlyNew, consumer == nil { throw ToolError("onlyNew needs a consumer name.") }
            let listings = try catalog.list(status: status, newFor: onlyNew ? consumer : nil)
            return listings.isEmpty ? "[]" : try Self.json(listings)
        case "get_record":
            return try Self.json(try record(arguments))
        case "mark_processed":
            guard let consumer = arguments["consumer"] as? String else { throw ToolError("consumer is required.") }
            let listing = try listing(arguments)
            var version: Int?
            if let raw = arguments["version"], !(raw is NSNull) {
                guard let number = raw as? Int else { throw ToolError("version must be an integer.") }
                version = number
            }
            let cursor = try consumers.markProcessed(
                recordId: listing.recordId, version: version, consumer: consumer, now: now()
            )
            return "Marked record \(cursor.conversationId.uuidString) version \(cursor.recordVersion) as processed by \(cursor.consumerName)."
        case "get_transcript":
            return Self.transcript(try record(arguments))
        default:
            throw ToolError("Unknown tool: \(name)")
        }
    }

    private func listing(_ arguments: [String: Any]) throws -> RecordListing {
        guard let text = arguments["recordId"] as? String else { throw ToolError("recordId is required.") }
        return try RecordCatalog.resolve(text, in: try catalog.list())
    }

    private func record(_ arguments: [String: Any]) throws -> MeetingRecord {
        try catalog.record(try listing(arguments).recordId)
    }

    static func transcript(_ record: MeetingRecord) -> String {
        let names = Dictionary(uniqueKeysWithValues: record.conversation.participants.map { ($0.id, $0.name) })
        var lines = [record.conversation.title]
        if record.transcript.segments.isEmpty { lines.append("No transcript.") }
        lines += record.transcript.segments.map { segment in
            let seconds = max(0, segment.startMs / 1000)
            let stamp = String(format: "%02d:%02d", seconds / 60, seconds % 60)
            return "[\(stamp)] \(segment.participantId.flatMap { names[$0] } ?? "?"): \(segment.text)"
        }
        return lines.joined(separator: "\n")
    }

    private static func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try MeetingRecord.encoder().encode(value), as: UTF8.self)
    }

    // MARK: Encoding

    private static func toolResult(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private static func encode(result: [String: Any], id: Any) -> String? {
        serialize(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func encode(error code: Int, message: String, id: Any) -> String? {
        serialize(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private static func serialize(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
