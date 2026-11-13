import Foundation
import XCTest
@testable import LorreCapture
@testable import LorreCore

final class RecordingCoordinatorTests: XCTestCase {
    private var root: URL!
    private var paths: LorrePaths!
    private var database: LorreDatabase!
    private var store: ConversationStore!
    private var engine: FakeCaptureEngine!
    private var coordinator: RecordingCoordinator!

    override func setUpWithError() throws {
        root = makeTemporaryRoot(named: "coordinator")
        paths = LorrePaths(root: root)
        database = try LorreDatabase(url: paths.database)
        store = ConversationStore(database: database)
        engine = FakeCaptureEngine()
        // A whole-second clock: the database stores dates to the millisecond.
        coordinator = RecordingCoordinator(
            paths: paths, database: database, engine: engine,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func size(_ id: UUID, _ kind: TrackKind) -> Int {
        RecordingCoordinator.fileSize(paths.conversationFolder(id).appendingPathComponent(kind.fileName))
    }

    func testStartCreatesConversationFolderTracksAndLock() async throws {
        let started = try await coordinator.start(source: .microphoneAndSystemAudio)

        let stored = try XCTUnwrap(store.conversation(id: started.id))
        XCTAssertEqual(stored.state, .recording)
        XCTAssertEqual(stored.captureSource, .microphoneAndSystemAudio)
        XCTAssertTrue(stored.title.hasPrefix("Conversation "))
        XCTAssertEqual(
            Set(try store.tracks(conversationId: started.id).map(\.relativePath)),
            [
                "conversations/\(started.id.uuidString)/microphone.caf",
                "conversations/\(started.id.uuidString)/system-audio.caf",
            ]
        )
        XCTAssertTrue(RecordingLock.isLive(in: paths.conversationFolder(started.id)))
        let active = await coordinator.active
        XCTAssertEqual(active?.id, started.id)
    }

    func testFailedStartLeavesNothingBehind() async throws {
        await engine.set(startError: .startFailed("no microphone"))
        do {
            _ = try await coordinator.start(source: .microphone)
            XCTFail("start should throw")
        } catch {
            XCTAssertEqual(error as? CaptureError, .startFailed("no microphone"))
        }
        XCTAssertEqual(try store.listConversations().count, 0)
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: paths.conversations.path)) ?? []
        XCTAssertEqual(folders, [])
        let active = await coordinator.active
        XCTAssertNil(active)
        // And a later start works.
        await engine.set(startError: nil)
        _ = try await coordinator.start(source: .microphone)
    }

    func testStopHandsOverForProcessing() async throws {
        let started = try await coordinator.start(source: .microphoneAndSystemAudio)
        let stopped = try await coordinator.stop()

        XCTAssertEqual(stopped.id, started.id)
        XCTAssertEqual(stopped.state, .processing)
        XCTAssertEqual(stopped.durationSeconds, 42)
        XCTAssertNil(stopped.lastError)
        XCTAssertEqual(try store.conversation(id: started.id), stopped)
        XCTAssertFalse(RecordingLock.isLive(in: paths.conversationFolder(started.id)))
        let active = await coordinator.active
        XCTAssertNil(active)
    }

    func testOneFailedTrackStillGetsProcessedAndKeepsBothFiles() async throws {
        await engine.set(trackFailures: [.system: "disk full"])
        let started = try await coordinator.start(source: .microphoneAndSystemAudio)
        let stopped = try await coordinator.stop()

        XCTAssertEqual(stopped.state, .processing)
        XCTAssertEqual(stopped.lastError, "Part of the recording could not be written (system: disk full).")
        XCTAssertGreaterThan(size(started.id, .microphone), 0)
        XCTAssertGreaterThan(size(started.id, .system), 0)
    }

    func testNoAudioAtAllBecomesInterruptedAndKeepsTheFiles() async throws {
        await engine.set(seconds: [.microphone: 0, .system: 0])
        await engine.set(trackFailures: [.microphone: "device lost", .system: "tap failed"])
        let started = try await coordinator.start(source: .microphoneAndSystemAudio)
        let stopped = try await coordinator.stop()

        XCTAssertEqual(stopped.state, .interrupted)
        XCTAssertEqual(stopped.lastError, "No audio was captured (microphone: device lost; system: tap failed).")
        let folder = paths.conversationFolder(started.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("microphone.caf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("system-audio.caf").path))
    }

    func testSecondStartIsRefusedAndDoesNotDisturbTheFirst() async throws {
        let first = try await coordinator.start(source: .microphone)
        do {
            _ = try await coordinator.start(source: .microphone)
            XCTFail("second start should throw")
        } catch {
            XCTAssertEqual(error as? CaptureError, .alreadyRecording)
        }
        XCTAssertEqual(try store.listConversations().count, 1)
        let startCount = await engine.startCount
        XCTAssertEqual(startCount, 1)
        let stopped = try await coordinator.stop()
        XCTAssertEqual(stopped.id, first.id)
    }

    func testStopWithoutRecordingThrows() async {
        do {
            _ = try await coordinator.stop()
            XCTFail("stop should throw")
        } catch {
            XCTAssertEqual(error as? CaptureError, .notRecording)
        }
    }

    /// The scenario of a database that cannot be written at Stop: the audio must stay, and the
    /// next launch must find it.
    func testDatabaseFailureAtStopKeepsAudioForRecovery() async throws {
        let started = try await coordinator.start(source: .microphoneAndSystemAudio)
        try await database.queue.write { db in
            // Any write to this conversation now fails.
            try db.execute(sql: """
                CREATE TRIGGER block_updates BEFORE UPDATE ON conversation
                BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END
                """)
        }
        do {
            _ = try await coordinator.stop()
            XCTFail("stop should surface the database error")
        } catch {}

        XCTAssertGreaterThan(size(started.id, .microphone), 0)
        XCTAssertGreaterThan(size(started.id, .system), 0)
        let stillActive = await coordinator.active
        XCTAssertNil(stillActive, "the recorder is free again")

        try await database.queue.write { db in try db.execute(sql: "DROP TRIGGER block_updates") }
        let report = try RecordingRecovery(paths: paths, database: database).run()
        XCTAssertEqual(report.recovered, [started.id])
        XCTAssertEqual(try store.conversation(id: started.id)?.state, .interrupted)
    }

    func testDefaultTitle() {
        let date = Date(timeIntervalSince1970: 1_791_453_600)
        XCTAssertEqual(
            RecordingCoordinator.defaultTitle(for: date, timeZone: TimeZone(identifier: "UTC")!),
            "Conversation 8 Oct 2026 at 10:00"
        )
    }
}
