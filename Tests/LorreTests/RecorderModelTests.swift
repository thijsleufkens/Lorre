import AVFoundation
import LorreCapture
import LorreCore
import XCTest
@testable import Lorre

private actor StubCaptureEngine: CaptureEngine {
    var startError: CaptureError?
    var writesAudio = true

    func set(startError: CaptureError?) { self.startError = startError }
    func set(writesAudio: Bool) { self.writesAudio = writesAudio }

    func start(source: CaptureSource, into folder: URL) async throws -> CaptureStart {
        if let startError { throw startError }
        for kind in source.trackKinds {
            let contents = writesAudio ? Data(repeating: 1, count: 16_384) : Data()
            try contents.write(to: folder.appendingPathComponent(kind.fileName))
        }
        return CaptureStart(startedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    func stop() async -> CaptureStop {
        CaptureStop(endedAt: Date(timeIntervalSince1970: 1_800_000_090), durationSeconds: 90)
    }

    func levels() async -> [TrackKind: Double] { [.microphone: 0.5] }

    var silent: Set<TrackKind> = []
    func set(silent: Set<TrackKind>) { self.silent = silent }
    func silentTracks() async -> Set<TrackKind> { silent }
}

private final class NotificationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func add(_ title: String) { lock.withLock { entries.append(title) } }
    var titles: [String] { lock.withLock { entries } }
}

@MainActor
final class RecorderModelTests: XCTestCase {
    private var root: URL!
    private var paths: LorrePaths!
    private var database: LorreDatabase!
    private var store: ConversationStore!
    private var engine: StubCaptureEngine!
    private var defaults: UserDefaults!
    private var processed: [UUID] = []
    private var notifications: NotificationLog!

    override func setUp() async throws {
        root = makeTemporaryRoot(named: "recorder-model")
        paths = LorrePaths(root: root)
        database = try LorreDatabase(url: paths.database)
        store = ConversationStore(database: database)
        engine = StubCaptureEngine()
        let suite = "recorder-model-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        notifications = NotificationLog()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// The queue's work marks the conversation as transcribed, like the real bridge does.
    private func makeModel(failProcessing: Bool = false) -> (RecorderModel, ProcessingQueue) {
        let store = self.store!
        let queue = ProcessingQueue { id in
            if failProcessing {
                try store.setState(.processing, lastError: "ASR failed", for: id)
                throw LorreError.processingFailed("ASR failed")
            }
            try store.setState(.proposed, lastError: nil, for: id)
        }
        let coordinator = RecordingCoordinator(paths: paths, database: database, engine: engine)
        let log = notifications!
        let model = RecorderModel(
            paths: paths, database: database, coordinator: coordinator, queue: queue,
            defaults: defaults, notify: { title, _ in log.add(title) },
            strings: { .english }
        )
        return (model, queue)
    }

    func testStartRecordStopGoesBackToIdleAndQueuesTheConversation() async throws {
        let (model, queue) = makeModel()
        XCTAssertEqual(model.phase, .idle)

        await model.start()
        XCTAssertTrue(model.isRecording)
        XCTAssertEqual(model.rows.first?.status, .recording)

        await model.stop()
        XCTAssertEqual(model.phase, .idle)
        await queue.waitUntilIdle()
        await model.refresh()

        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.rows[0].status, .ready)
        XCTAssertEqual(model.rows[0].durationSeconds, 90)
        XCTAssertNil(model.message)
    }

    func testFailedStartReturnsToIdleWithAMessage() async {
        await engine.set(startError: .permissionDenied("No microphone access."))
        let (model, _) = makeModel()
        await model.start()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.message, "Could not start recording. No microphone access.")
        XCTAssertEqual(model.rows, [])
    }

    func testRecordingWithoutAudioIsNotQueued() async throws {
        await engine.set(writesAudio: false)
        let (model, queue) = makeModel()
        await model.start()
        await model.stop()
        await queue.waitUntilIdle()
        await model.refresh()
        XCTAssertEqual(model.rows.first?.status, .interrupted)
        XCTAssertEqual(model.message, "No audio was captured.")
    }

    func testFailedProcessingShowsRetryAndNotifies() async throws {
        let (model, queue) = makeModel(failProcessing: true)
        model.observeQueue()
        await model.start()
        await model.stop()
        await queue.waitUntilIdle()
        try await Task.sleep(for: .milliseconds(100))
        await model.refresh()
        XCTAssertEqual(model.rows.first?.status, .failed)
        XCTAssertEqual(model.rows.first?.error, "ASR failed")
        XCTAssertEqual(notifications.titles, [Strings.english.notifyFailedTitle])
    }

    func testSuccessfulProcessingNotifies() async throws {
        let (model, queue) = makeModel()
        model.observeQueue()
        await model.start()
        await model.stop()
        await queue.waitUntilIdle()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(notifications.titles, [Strings.english.notifyReadyTitle])
    }

    func testSilentMicrophoneIsReportedWhileRecording() async throws {
        await engine.set(silent: [.microphone])
        let (model, _) = makeModel()
        await model.start()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.message, CaptureAdvice.silentMicrophone)
        XCTAssertEqual(notifications.titles, [Strings.english.notifyNoSoundTitle])
        await model.stop()
    }

    func testNotificationsFollowTheLanguageAndHideRawErrors() async throws {
        let store = self.store!
        let queue = ProcessingQueue { id in
            try store.setState(.processing, lastError: "ASR failed", for: id)
            throw LorreError.processingFailed("ASR failed")
        }
        let bodies = NotificationLog()
        let model = RecorderModel(
            paths: paths, database: database,
            coordinator: RecordingCoordinator(paths: paths, database: database, engine: engine),
            queue: queue, defaults: defaults,
            notify: { _, body in bodies.add(body) }, strings: { .dutch }
        )
        model.observeQueue()
        await model.start()
        await model.stop()
        await queue.waitUntilIdle()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(bodies.titles.count, 1)
        XCTAssertTrue(bodies.titles[0].hasSuffix(Strings.dutch.errorGeneric), bodies.titles[0])
        XCTAssertFalse(bodies.titles[0].contains("ASR"))
    }

    func testSourceIsRemembered() {
        let (model, _) = makeModel()
        XCTAssertEqual(model.source, .microphoneAndSystemAudio)
        model.source = .microphone
        let (again, _) = makeModel()
        XCTAssertEqual(again.source, .microphone)
    }

    func testStartWithAnExplicitSourceUsesIt() async {
        let (model, _) = makeModel()
        await model.start(source: .systemAudio)
        XCTAssertEqual(model.source, .systemAudio)
        XCTAssertEqual(try? store.listConversations().first?.conversation.captureSource, .systemAudio)
        await model.stop()
    }

    func testRecoveryAtLaunchQueuesAbandonedRecordings() async throws {
        // A recording another run of the app left behind.
        let abandoned = Conversation(
            title: "Abandoned", state: .recording, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            captureSource: .microphone
        )
        try store.save(abandoned)
        let folder = paths.conversationFolder(abandoned.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: folder.appendingPathComponent("microphone.caf"))

        let (model, queue) = makeModel()
        let report = await model.recoverAtLaunch(database: database)
        await queue.waitUntilIdle()
        await model.refresh()

        XCTAssertEqual(report?.recovered, [abandoned.id])
        XCTAssertEqual(model.rows.first?.status, .ready)
        XCTAssertEqual(model.message?.contains("recovered"), true)
        XCTAssertEqual(notifications.titles.first, Strings.english.notifyRecoveredTitle)
    }

    func testNothingToRecoverSaysNothing() async {
        let (model, _) = makeModel()
        let report = await model.recoverAtLaunch(database: database)
        XCTAssertEqual(report, RecoveryReport())
        XCTAssertNil(model.message)
        XCTAssertEqual(notifications.titles, [])
    }

    func testElapsedFormatting() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(MenuBarRecorderView.elapsed(from: start, to: start.addingTimeInterval(0)), "00:00")
        XCTAssertEqual(MenuBarRecorderView.elapsed(from: start, to: start.addingTimeInterval(75)), "01:15")
        XCTAssertEqual(MenuBarRecorderView.elapsed(from: start, to: start.addingTimeInterval(3725)), "62:05")
        XCTAssertEqual(MenuBarRecorderView.elapsed(from: start, to: start.addingTimeInterval(-5)), "00:00")
    }
}

final class ShowCommandTests: XCTestCase {
    private let conversation = Conversation(
        id: UUID(uuidString: "ABCDEF12-1111-1111-1111-111111111111")!,
        title: "Call", state: .proposed, startedAt: Date(timeIntervalSince1970: 1_791_453_600)
    )

    func testTextTranscriptHasTimesAndNames() throws {
        let anna = Participant(conversationId: conversation.id, name: "Anna")
        let version = UUID()
        let output = try ShowCommand.render(
            conversation: conversation,
            participants: [anna],
            segments: [
                Segment(transcriptVersionId: version, participantId: anna.id, startMs: 5_000, endMs: 6_000, text: "Hallo"),
                Segment(transcriptVersionId: version, participantId: nil, startMs: 125_000, endMs: 126_000, text: "Dag"),
            ],
            json: false
        )
        XCTAssertEqual(output, "Call  (proposed)\n[00:05] Anna: Hallo\n[02:05] ?: Dag")
    }

    func testEmptyTranscriptAndErrorAreShown() throws {
        var interrupted = conversation
        interrupted.state = .interrupted
        interrupted.lastError = "The recording was interrupted before it was stopped."
        let output = try ShowCommand.render(conversation: interrupted, participants: [], segments: [], json: false)
        XCTAssertEqual(
            output,
            "Call  (interrupted)\nNote: The recording was interrupted before it was stopped.\nNo transcript yet."
        )
    }

    func testJSON() throws {
        let output = try ShowCommand.render(
            conversation: conversation, participants: [],
            segments: [Segment(transcriptVersionId: UUID(), startMs: 0, endMs: 10, text: "Hallo")],
            json: true
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, conversation.id.uuidString)
        XCTAssertEqual((object["segments"] as? [[String: Any]])?.first?["text"] as? String, "Hallo")
    }

    func testResolveByPrefix() throws {
        let other = Conversation(
            id: UUID(uuidString: "ABCD0000-2222-2222-2222-222222222222")!,
            title: "Other", state: .proposed, startedAt: Date()
        )
        XCTAssertEqual(try ShowCommand.resolve("abcdef", in: [conversation, other]).id, conversation.id)
        XCTAssertThrowsError(try ShowCommand.resolve("abcd", in: [conversation, other]))
        XCTAssertThrowsError(try ShowCommand.resolve("ffff", in: [conversation, other]))
    }
}
