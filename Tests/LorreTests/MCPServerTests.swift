import Foundation
import LorreCore
import XCTest
@testable import Lorre

/// A database with exported records in a temp folder, built only through LorreCore's public API.
final class ExportedRecords {
    let folder: URL
    let database: LorreDatabase
    let exporter: RecordExporter
    private let store: ConversationStore
    private let review: ReviewStore

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LorreMCPTests-\(UUID().uuidString)", isDirectory: true)
        database = try LorreDatabase.inMemory()
        store = ConversationStore(database: database)
        review = ReviewStore(database: database)
        let folder = self.folder
        exporter = RecordExporter(
            database: database, folder: { folder }, language: .english,
            now: { Date(timeIntervalSince1970: 1_791_460_000) }
        )
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    @discardableResult
    func add(
        id: UUID = UUID(), title: String, startedAt: TimeInterval, approved: Bool
    ) throws -> Conversation {
        let conversation = Conversation(
            id: id, title: title, type: .network, state: .proposed,
            startedAt: Date(timeIntervalSince1970: startedAt), durationSeconds: 120
        )
        try store.save(conversation)
        let thijs = Participant(conversationId: id, name: "Thijs", isUser: true)
        let anna = Participant(conversationId: id, name: "Anna")
        try store.saveParticipants([thijs, anna])
        let version = TranscriptVersion(conversationId: id, engine: "test-engine")
        try store.saveTranscript(version: version, segments: [
            Segment(transcriptVersionId: version.id, participantId: thijs.id, startMs: 1_000, endMs: 4_000, text: "Ik stuur de offerte."),
            Segment(transcriptVersionId: version.id, participantId: anna.id, startMs: 65_000, endMs: 69_000, text: "Dan geef ik je naam door."),
        ])
        if approved {
            try review.addOutcome(conversationId: id, kind: .decision, text: "We doen het", source: .user)
            try review.finishReview(id)
            try exporter.exportApproved(id)
        } else {
            try exporter.exportDraft(id)
        }
        return conversation
    }
}

final class MCPServerTests: XCTestCase {
    private var records: ExportedRecords!
    private var server: MCPServer!
    private var approved: Conversation!
    private var draft: Conversation!

    override func setUpWithError() throws {
        records = try ExportedRecords()
        approved = try records.add(
            id: UUID(uuidString: "AAAAAAAA-1111-1111-1111-111111111111")!,
            title: "Approved call", startedAt: 1_791_100_000, approved: true
        )
        draft = try records.add(
            id: UUID(uuidString: "BBBBBBBB-2222-2222-2222-222222222222")!,
            title: "Draft call", startedAt: 1_791_000_000, approved: false
        )
        server = MCPServer(database: records.database, now: { Date(timeIntervalSince1970: 1_791_500_000) })
    }

    // MARK: Helpers

    private func send(_ object: [String: Any]) throws -> [String: Any]? {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let reply = server.handle(line: String(decoding: data, as: UTF8.self)) else { return nil }
        XCTAssertFalse(reply.contains("\n"), "a reply must be one line")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
    }

    private func call(_ tool: String, _ arguments: [String: Any]) throws -> (text: String, isError: Bool) {
        let reply = try XCTUnwrap(send([
            "jsonrpc": "2.0", "id": 7, "method": "tools/call",
            "params": ["name": tool, "arguments": arguments],
        ]))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        let content = try XCTUnwrap((result["content"] as? [[String: Any]])?.first)
        XCTAssertEqual(content["type"] as? String, "text")
        return (try XCTUnwrap(content["text"] as? String), try XCTUnwrap(result["isError"] as? Bool))
    }

    private func listed(_ arguments: [String: Any]) throws -> [[String: Any]] {
        let (text, isError) = try call("list_records", arguments)
        XCTAssertFalse(isError, text)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }

    // MARK: Protocol

    func testInitializeHandshake() throws {
        let reply = try XCTUnwrap(send([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2025-03-26", "capabilities": [String: Any](),
                       "clientInfo": ["name": "test", "version": "1"]],
        ]))
        XCTAssertEqual(reply["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(reply["id"] as? Int, 1)
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        let info = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(info["name"] as? String, "lorre")
        XCTAssertNotNil(info["version"] as? String)
    }

    func testInitializeWithUnknownVersionAnswersWithLatest() throws {
        let reply = try XCTUnwrap(send([
            "jsonrpc": "2.0", "id": "abc", "method": "initialize", "params": ["protocolVersion": "1999-01-01"],
        ]))
        XCTAssertEqual(reply["id"] as? String, "abc")
        XCTAssertEqual(
            (reply["result"] as? [String: Any])?["protocolVersion"] as? String,
            MCPServer.supportedProtocolVersions[0]
        )
    }

    func testInitializedNotificationYieldsNoOutput() throws {
        XCTAssertNil(try send(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        // Also an unknown method, when it is a notification.
        XCTAssertNil(try send(["jsonrpc": "2.0", "method": "does/not/exist"]))
        XCTAssertNil(server.handle(line: ""))
    }

    func testPing() throws {
        let reply = try XCTUnwrap(send(["jsonrpc": "2.0", "id": 3, "method": "ping"]))
        XCTAssertEqual((reply["result"] as? [String: Any])?.count, 0)
    }

    func testUnknownMethodIsMethodNotFound() throws {
        let reply = try XCTUnwrap(send(["jsonrpc": "2.0", "id": 4, "method": "resources/list"]))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertEqual(reply["id"] as? Int, 4)
        XCTAssertNil(reply["result"])
    }

    func testMalformedJSONIsParseError() throws {
        let reply = try XCTUnwrap(server.handle(line: "{not json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? Int, -32700)
        XCTAssertTrue(object["id"] is NSNull)
    }

    func testToolsList() throws {
        let reply = try XCTUnwrap(send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"]))
        let tools = try XCTUnwrap((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["list_records", "get_record", "mark_processed", "get_transcript"])
        for tool in tools {
            XCTAssertNotNil(tool["description"] as? String)
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
            XCTAssertEqual(schema["type"] as? String, "object")
            XCTAssertNotNil(schema["properties"] as? [String: Any])
        }
        let required = { (name: String) in
            tools.first { $0["name"] as? String == name }
                .flatMap { ($0["inputSchema"] as? [String: Any])?["required"] as? [String] }
        }
        XCTAssertEqual(required("get_record"), ["recordId"])
        XCTAssertEqual(required("mark_processed"), ["recordId", "consumer"])
    }

    // MARK: Tools

    func testListRecords() throws {
        let all = try listed([:])
        XCTAssertEqual(all.map { $0["title"] as? String }, ["Approved call", "Draft call"])
        XCTAssertEqual(all[0]["recordId"] as? String, approved.id.uuidString)
        XCTAssertEqual(all[0]["recordVersion"] as? Int, 1)
        XCTAssertEqual(all[0]["status"] as? String, "approved")

        XCTAssertEqual(try listed(["status": "draft"]).count, 1)
        XCTAssertEqual(try listed(["status": "approved"]).first?["title"] as? String, "Approved call")
    }

    func testListRecordsRejectsBadArguments() throws {
        let badStatus = try call("list_records", ["status": "final"])
        XCTAssertTrue(badStatus.isError)
        XCTAssertTrue(badStatus.text.contains("draft"))
        let noConsumer = try call("list_records", ["onlyNew": true])
        XCTAssertTrue(noConsumer.isError)
        XCTAssertTrue(noConsumer.text.contains("consumer"))
    }

    func testGetRecordByFullIdAndByPrefix() throws {
        for id in [approved.id.uuidString, "aaaaaaaa", "AAAA"] {
            let (text, isError) = try call("get_record", ["recordId": id])
            XCTAssertFalse(isError, text)
            let record = try MeetingRecord.decoder().decode(MeetingRecord.self, from: Data(text.utf8))
            XCTAssertEqual(record.recordId, approved.id)
            XCTAssertEqual(record.outcomes.map(\.text), ["We doen het"])
            XCTAssertEqual(record.transcript.segments.count, 2)
        }
    }

    func testGetRecordUnknownOrMissingIdIsAToolError() throws {
        let unknown = try call("get_record", ["recordId": "ffff"])
        XCTAssertTrue(unknown.isError)
        XCTAssertTrue(unknown.text.contains("ffff"))
        XCTAssertTrue(try call("get_record", [:]).isError)
    }

    func testGetRecordWithMissingFileExplainsIt() throws {
        let listing = try XCTUnwrap(RecordCatalog(database: records.database).list().first { $0.recordId == draft.id })
        try FileManager.default.removeItem(atPath: listing.path)
        let (text, isError) = try call("get_record", ["recordId": draft.id.uuidString])
        XCTAssertTrue(isError)
        XCTAssertTrue(text.contains("gone"), text)
    }

    func testGetTranscript() throws {
        let (text, isError) = try call("get_transcript", ["recordId": "AAAAAAAA"])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(text, """
            Approved call
            [00:01] Thijs: Ik stuur de offerte.
            [01:05] Anna: Dan geef ik je naam door.
            """)
    }

    func testMarkProcessedThenOnlyNew() throws {
        XCTAssertEqual(try listed(["consumer": "agent", "onlyNew": true]).count, 2)

        let (text, isError) = try call("mark_processed", ["recordId": "aaaaaaaa", "consumer": "agent"])
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("version 1"))

        XCTAssertEqual(try listed(["consumer": "agent", "onlyNew": true]).map { $0["title"] as? String }, ["Draft call"])
        XCTAssertEqual(try listed(["consumer": "other", "onlyNew": true]).count, 2)
        XCTAssertEqual(try listed(["consumer": "agent"]).count, 2)
        XCTAssertEqual(
            try ConsumerStore(database: records.database).cursors(consumer: "agent").first?.processedAt,
            Date(timeIntervalSince1970: 1_791_500_000)
        )
    }

    func testMarkProcessedFailuresAreToolErrors() throws {
        XCTAssertTrue(try call("mark_processed", ["recordId": "aaaaaaaa", "consumer": " "]).isError)
        XCTAssertTrue(try call("mark_processed", ["recordId": "aaaaaaaa"]).isError)
        let badVersion = try call("mark_processed", ["recordId": "aaaaaaaa", "consumer": "agent", "version": 9])
        XCTAssertTrue(badVersion.isError)
        XCTAssertTrue(badVersion.text.contains("version 9"))
        XCTAssertTrue(try call("mark_processed", ["recordId": "aaaaaaaa", "consumer": "agent", "version": "one"]).isError)
        XCTAssertFalse(try call("mark_processed", ["recordId": "aaaaaaaa", "consumer": "agent", "version": 1]).isError)
    }

    func testUnknownToolIsAnError() throws {
        let reply = try XCTUnwrap(send([
            "jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": ["name": "delete_everything", "arguments": [String: Any]()],
        ]))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32602)
    }
}
