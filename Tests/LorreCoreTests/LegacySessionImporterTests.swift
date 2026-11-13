import XCTest
@testable import LorreCore

final class LegacySessionImporterTests: XCTestCase {
    private let sessionId = "11111111-1111-1111-1111-111111111111"
    private let importDate = Date(timeIntervalSince1970: 1_800_000_000)
    private var root: TemporaryRoot!
    private var database: LorreDatabase!
    private var store: ConversationStore!

    override func setUpWithError() throws {
        root = try TemporaryRoot()
        database = try LorreDatabase.inMemory()
        store = ConversationStore(database: database)
    }

    private func runImport() throws -> LegacyImportReport {
        let date = importDate
        return try LegacySessionImporter(paths: root.paths, database: database, now: { date }).run()
    }

    func testImportsASessionWithItsTranscript() throws {
        try root.addLegacySession(
            folder: sessionId,
            manifest: Fixture.data("session-manifest-v1-with-version"),
            transcript: Fixture.data("transcript-document-v1"),
            files: ["audio.caf", "microphone.caf"]
        )

        let report = try runImport()
        let id = try XCTUnwrap(UUID(uuidString: sessionId))
        XCTAssertEqual(report.imported, [id])
        XCTAssertEqual(report.skipped, [])

        let conversation = try XCTUnwrap(store.conversation(id: id))
        XCTAssertEqual(conversation.title, "Versioned Session")
        XCTAssertEqual(conversation.state, .proposed)
        XCTAssertEqual(conversation.type, .other)
        XCTAssertEqual(conversation.durationSeconds, 1800)
        XCTAssertEqual(conversation.startedAt, ISO8601DateFormatter().date(from: "2026-01-15T09:55:00Z"))
        XCTAssertEqual(conversation.importedAt, importDate)

        let participants = try store.participants(conversationId: id)
        XCTAssertEqual(Set(participants.map(\.name)), ["Speaker S1", "Unknown speaker"])
        XCTAssertEqual(Set(participants.compactMap(\.sourceLabel)), ["S1", "UNK"])
        XCTAssertFalse(participants.contains(where: \.isUser))

        let version = try XCTUnwrap(store.currentTranscriptVersion(conversationId: id))
        XCTAssertEqual(version.engine, "TestEngine")
        XCTAssertEqual(version.languageHint, "en")

        let segments = try store.currentSegments(conversationId: id)
        XCTAssertEqual(segments.map(\.text), ["Hello world"])
        XCTAssertEqual(segments[0].id, UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        XCTAssertEqual(segments[0].participantId, participants.first { $0.sourceLabel == "S1" }?.id)

        // Only files that exist become tracks; system-audio.caf is named in the manifest but absent.
        let tracks = try store.tracks(conversationId: id)
        XCTAssertEqual(
            Set(tracks.map { "\($0.kind.rawValue):\($0.relativePath)" }),
            ["mix:sessions/\(sessionId)/audio.caf", "microphone:sessions/\(sessionId)/microphone.caf"]
        )
    }

    func testImportsAManifestWithoutSchemaVersion() throws {
        try root.addLegacySession(
            folder: sessionId,
            manifest: Fixture.data("session-manifest-v1-pre-version"),
            transcript: Fixture.data("transcript-document-v1")
        )
        XCTAssertEqual(try runImport().imported.count, 1)
        XCTAssertEqual(try store.listConversations().first?.conversation.title, "Pre-version Session")
    }

    func testSessionWithoutTranscriptIsInterrupted() throws {
        try root.addLegacySession(folder: sessionId, manifest: Fixture.data("session-manifest-v1-with-version"))
        _ = try runImport()
        let id = try XCTUnwrap(UUID(uuidString: sessionId))
        XCTAssertEqual(try store.conversation(id: id)?.state, .interrupted)
        XCTAssertNil(try store.currentTranscriptVersion(conversationId: id))
        XCTAssertEqual(try store.participants(conversationId: id), [])
    }

    func testSessionThatNeverFinishedIsInterruptedEvenWithATranscript() throws {
        let manifest = Data("""
            {"id":"\(sessionId)","title":"Stuck","status":"processing","createdAt":"2026-01-15T10:00:00Z"}
            """.utf8)
        try root.addLegacySession(
            folder: sessionId, manifest: manifest, transcript: Fixture.data("transcript-document-v1")
        )
        _ = try runImport()
        let id = try XCTUnwrap(UUID(uuidString: sessionId))
        XCTAssertEqual(try store.conversation(id: id)?.state, .interrupted)
        // The partial transcript is still worth keeping.
        XCTAssertEqual(try store.currentSegments(conversationId: id).count, 1)
    }

    func testRunningTwiceDoesNotDuplicate() throws {
        try root.addLegacySession(
            folder: sessionId,
            manifest: Fixture.data("session-manifest-v1-with-version"),
            transcript: Fixture.data("transcript-document-v1")
        )
        _ = try runImport()
        let second = try runImport()

        XCTAssertEqual(second.imported, [])
        XCTAssertEqual(second.alreadyPresent.count, 1)
        let list = try store.listConversations()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].segmentCount, 1)
        XCTAssertEqual(list[0].participantNames.count, 2)
    }

    func testSecondImportDoesNotOverwriteLaterChanges() throws {
        try root.addLegacySession(
            folder: sessionId,
            manifest: Fixture.data("session-manifest-v1-with-version"),
            transcript: Fixture.data("transcript-document-v1")
        )
        _ = try runImport()
        let id = try XCTUnwrap(UUID(uuidString: sessionId))
        var conversation = try XCTUnwrap(store.conversation(id: id))
        conversation.title = "Renamed in the new app"
        try store.save(conversation)

        _ = try runImport()
        XCTAssertEqual(try store.conversation(id: id)?.title, "Renamed in the new app")
    }

    func testCorruptSessionIsSkippedAndOthersStillImport() throws {
        let broken = "22222222-2222-2222-2222-222222222222"
        let empty = "33333333-3333-3333-3333-333333333333"
        try root.addLegacySession(folder: broken, manifest: Data("{ not json".utf8))
        try FileManager.default.createDirectory(
            at: root.paths.legacySessions.appendingPathComponent(empty), withIntermediateDirectories: true
        )
        try root.addLegacySession(
            folder: sessionId,
            manifest: Fixture.data("session-manifest-v1-with-version"),
            transcript: Fixture.data("transcript-document-v1")
        )

        let report = try runImport()
        XCTAssertEqual(report.imported.count, 1)
        XCTAssertEqual(report.skipped, [
            .init(folder: broken, reason: "session.json could not be read"),
            .init(folder: empty, reason: "no session.json"),
        ])
    }

    func testCorruptTranscriptSkipsTheSessionInsteadOfImportingItEmpty() throws {
        try root.addLegacySession(
            folder: sessionId,
            manifest: Fixture.data("session-manifest-v1-with-version"),
            transcript: Data("[]".utf8)
        )
        let report = try runImport()
        XCTAssertEqual(report.skipped, [.init(folder: sessionId, reason: "transcript.json could not be read")])
        XCTAssertEqual(try store.listConversations().count, 0)
    }

    func testFolderNameWinsOverTheIdInsideTheFile() throws {
        let folder = "44444444-4444-4444-4444-444444444444"
        try root.addLegacySession(folder: folder, manifest: Fixture.data("session-manifest-v1-with-version"))
        XCTAssertEqual(try runImport().imported, [UUID(uuidString: folder)])
    }

    func testTwoSessionsSharingSegmentIdsBothImport() throws {
        let copy = "55555555-5555-5555-5555-555555555555"
        for folder in [sessionId, copy] {
            try root.addLegacySession(
                folder: folder,
                manifest: Fixture.data("session-manifest-v1-with-version"),
                transcript: Fixture.data("transcript-document-v1")
            )
        }
        let report = try runImport()
        XCTAssertEqual(report.imported.count, 2)
        XCTAssertEqual(try store.listConversations().map(\.segmentCount), [1, 1])
    }

    func testMissingLegacyFolderIsNotAnError() throws {
        XCTAssertEqual(try runImport(), LegacyImportReport())
    }

    func testNeverWritesInsideTheLegacyFolder() throws {
        try root.addLegacySession(
            folder: sessionId,
            manifest: Fixture.data("session-manifest-v1-with-version"),
            transcript: Fixture.data("transcript-document-v1"),
            files: ["audio.caf"]
        )
        let before = try root.legacySnapshot()
        _ = try runImport()
        _ = try runImport()
        XCTAssertEqual(try root.legacySnapshot(), before)
    }
}
