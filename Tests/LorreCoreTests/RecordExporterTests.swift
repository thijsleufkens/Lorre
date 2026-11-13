import XCTest
@testable import LorreCore

final class RecordExporterTests: XCTestCase {
    private var root: TemporaryRoot!
    private var folder: URL!
    private var database: LorreDatabase!
    private var store: ConversationStore!
    private var review: ReviewStore!
    private var exporter: RecordExporter!
    private var conversation: Conversation!
    private var thijs: Participant!
    private var anna: Participant!
    private var segments: [Segment] = []
    private let utc = TimeZone(identifier: "UTC")!

    override func setUpWithError() throws {
        root = try TemporaryRoot()
        folder = root.paths.root.appendingPathComponent("records", isDirectory: true)
        database = try LorreDatabase.inMemory()
        store = ConversationStore(database: database)
        review = ReviewStore(database: database)
        let folder = self.folder!
        exporter = RecordExporter(
            database: database, folder: { folder }, language: .dutch,
            now: { Date(timeIntervalSince1970: 1_791_460_000) }
        )
        conversation = Conversation(
            title: "Call met Anna: fotografie/maakindustrie", type: .network, state: .proposed,
            startedAt: Date(timeIntervalSince1970: 1_791_453_600), durationSeconds: 1741
        )
        try store.save(conversation)
        thijs = Participant(conversationId: conversation.id, name: "Thijs", isUser: true)
        anna = Participant(conversationId: conversation.id, name: "Anna")
        try store.saveParticipants([thijs, anna])
        let version = TranscriptVersion(conversationId: conversation.id, engine: "test-engine")
        segments = [
            Segment(transcriptVersionId: version.id, participantId: thijs.id, startMs: 1_000, endMs: 4_000, text: "Ik stuur morgen de offerte."),
            Segment(transcriptVersionId: version.id, participantId: thijs.id, startMs: 4_000, endMs: 5_000, text: "Echt waar."),
            Segment(transcriptVersionId: version.id, participantId: anna.id, startMs: 65_000, endMs: 69_000, text: "Dan geef ik je naam door."),
        ]
        try store.saveTranscript(version: version, segments: segments)
    }

    private func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    func testDraftHasTheTranscriptAndNoOutcomes() throws {
        try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "voorstel", source: .model)

        let exported = try XCTUnwrap(exporter.exportDraft(conversation.id))

        XCTAssertEqual(exported.record.status, .draft)
        XCTAssertEqual(exported.record.recordVersion, 0)
        XCTAssertEqual(exported.record.outcomes, [])
        XCTAssertEqual(exported.record.transcript.segments.count, 3)
        XCTAssertNil(exported.record.approvedAt)
        XCTAssertEqual(files(), [
            "2026-10-08 Call met Anna fotografie maakindustrie.json",
            "2026-10-08 Call met Anna fotografie maakindustrie.md",
        ])
        XCTAssertTrue(try String(contentsOf: exported.markdown, encoding: .utf8).contains("_Concept:"))
    }

    func testApprovedRecordCarriesOnlyApprovedOutcomes() throws {
        let action = try review.addOutcome(
            conversationId: conversation.id, kind: .myAction, text: "Offerte sturen",
            ownerParticipantId: thijs.id, due: Date(timeIntervalSince1970: 1_791_540_000), evidence: [segments[0]]
        )
        let rejected = try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "onzin", source: .model)
        try review.setStatus(.rejected, for: rejected.id)
        try review.addOutcome(conversationId: conversation.id, kind: .information, text: "nog voorgesteld", source: .model)

        let exported = try exporter.exportApproved(conversation.id)
        let decoded = try MeetingRecord.decoder().decode(MeetingRecord.self, from: Data(contentsOf: exported.json))

        XCTAssertEqual(decoded, exported.record)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.recordId, conversation.id)
        XCTAssertEqual(decoded.recordVersion, 1)
        XCTAssertEqual(decoded.status, .approved)
        XCTAssertEqual(decoded.approvedAt, Date(timeIntervalSince1970: 1_791_460_000))
        XCTAssertEqual(decoded.outcomes.map(\.id), [action.id], "proposed and rejected items never leave Lorre")
        XCTAssertEqual(decoded.outcomes[0].ownerId, thijs.id)
        XCTAssertEqual(decoded.outcomes[0].evidence.segmentIds, [segments[0].id])
        XCTAssertEqual(decoded.conversation.participants.map(\.name), ["Thijs", "Anna"])
        XCTAssertEqual(decoded.conversation.participants.first?.isUser, true)
        XCTAssertEqual(decoded.transcript.engine, "test-engine")
    }

    func testJSONUsesTheContractFieldNames() throws {
        try review.addOutcome(conversationId: conversation.id, kind: .theirCommitment, text: "x", ownerParticipantId: anna.id)
        let exported = try exporter.exportApproved(conversation.id)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: exported.json)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "recordId", "recordVersion", "status", "conversation", "outcomes", "transcript", "approvedAt"])
        XCTAssertEqual(object["status"] as? String, "approved")
        let outcome = try XCTUnwrap((object["outcomes"] as? [[String: Any]])?.first)
        XCTAssertEqual(outcome["kind"] as? String, "theirCommitment")
        XCTAssertEqual(outcome["ownerId"] as? String, anna.id.uuidString)
        XCTAssertNotNil(outcome["evidence"])
        XCTAssertEqual((object["conversation"] as? [String: Any])?["type"] as? String, "network")
        XCTAssertEqual((object["conversation"] as? [String: Any])?["startedAt"] as? String, "2026-10-08T10:00:00Z")
    }

    func testReapprovalAfterAChangeIsTheNextVersion() throws {
        try review.finishReview(conversation.id)
        XCTAssertEqual(try exporter.exportApproved(conversation.id).record.recordVersion, 1)
        try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "later toegevoegd")
        try review.finishReview(conversation.id)
        let second = try exporter.exportApproved(conversation.id)
        XCTAssertEqual(second.record.recordVersion, 2)
        XCTAssertEqual(second.record.outcomes.count, 1)
        XCTAssertEqual(files().count, 2, "the same two files are replaced")
        XCTAssertEqual(try exporter.latestExport(conversation.id)?.version, 2)
    }

    func testDraftNeverReplacesAnApprovedRecord() throws {
        try exporter.exportApproved(conversation.id)
        XCTAssertNil(try exporter.exportDraft(conversation.id))
        XCTAssertEqual(try exporter.latestExport(conversation.id)?.status, .approved)
    }

    func testRenamedConversationReplacesItsOldFiles() throws {
        try exporter.exportDraft(conversation.id)
        try review.updateConversation(conversation.id, title: "Anna")
        try exporter.exportApproved(conversation.id)
        XCTAssertEqual(files(), ["2026-10-08 Anna.json", "2026-10-08 Anna.md"])
    }

    func testTwoConversationsWithTheSameNameDoNotOverwriteEachOther() throws {
        var twin = conversation!
        twin.id = UUID()
        try store.save(twin)
        try exporter.exportApproved(conversation.id)
        try exporter.exportApproved(twin.id)
        XCTAssertEqual(files().filter { $0.hasSuffix(".json") }.count, 2)
        XCTAssertTrue(files().contains { $0.contains(twin.id.uuidString.prefix(8).lowercased()) })
    }

    func testMarkdownIsReadable() throws {
        try review.addOutcome(
            conversationId: conversation.id, kind: .myAction, text: "Offerte sturen",
            ownerParticipantId: thijs.id, evidence: [segments[0]]
        )
        try review.addOutcome(
            conversationId: conversation.id, kind: .theirCommitment, text: "Naam doorgeven",
            ownerParticipantId: anna.id, evidence: [segments[2]]
        )
        try review.addOutcome(conversationId: conversation.id, kind: .decision, text: "Niet naar het event")
        let record = try exporter.buildRecord(conversationId: conversation.id, status: .approved)

        let markdown = RecordMarkdown.render(record, language: .dutch, timeZone: utc)

        XCTAssertEqual(markdown, """
            # Call met Anna: fotografie/maakindustrie

            8 oktober 2026 om 10:00 · 29 min · Netwerkgesprek
            Deelnemers: Thijs, Anna

            ## Mijn acties

            - [ ] Offerte sturen — Thijs, 00:01

            ## Toezeggingen van anderen

            - [ ] Naam doorgeven — Anna, 01:05

            ## Besluiten

            - Niet naar het event

            ## Transcript

            **Thijs** (00:01): Ik stuur morgen de offerte. Echt waar.

            **Anna** (01:05): Dan geef ik je naam door.

            """)
    }

    func testFileNamesAreSafe() {
        XCTAssertEqual(RecordExporter.safeFileName("a/b:c*?\"<>|\nd"), "a b c d")
        XCTAssertEqual(RecordExporter.safeFileName("  ..  "), "conversation")
        XCTAssertEqual(RecordExporter.safeFileName(String(repeating: "x", count: 200)).count, 80)
    }
}
