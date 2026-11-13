import AVFoundation
import LorreCapture
import LorreCore
import XCTest
@testable import Lorre

private struct FailingTranscriptionService: TranscriptionService {
    func ensureModelsReady(onProgress: (@Sendable (ProcessingUpdate) async -> Void)?) async throws {}
    func setVocabularyBoostingConfiguration(_ configuration: VocabularyBoostingConfiguration) async {}
    func setBatchTranscriptionLanguage(_ language: BatchTranscriptionLanguage) async {}
    func transcribe(url: URL, sessionTitle: String, source: RecordingSource) async throws -> TranscriptionResult {
        throw LorreError.processingFailed("simulated ASR failure")
    }
}

final class ConversationProcessorTests: XCTestCase {
    private var root: URL!
    private var paths: LorrePaths!
    private var database: LorreDatabase!
    private var store: ConversationStore!

    override func setUpWithError() throws {
        root = makeTemporaryRoot(named: "processor")
        paths = LorrePaths(root: root)
        database = try LorreDatabase(url: paths.database)
        store = ConversationStore(database: database)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func processor(failing: Bool = false) -> ConversationProcessor {
        ConversationProcessor(
            paths: paths,
            database: database,
            transcription: failing ? FailingTranscriptionService() : MockTranscriptionService(),
            diarization: MockSpeakerDiarizationService()
        )
    }

    private func writeTone(_ url: URL, seconds: Double) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let samples = (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * 0.05)) * 0.4 }
        try RecorderAudioUtilities.write(samples: samples, to: url, format: format)
    }

    private func makeConversation(
        state: ConversationState = .processing,
        source: CaptureSource = .microphoneAndSystemAudio
    ) throws -> Conversation {
        let conversation = Conversation(
            title: "Test call", state: state, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 2, captureSource: source
        )
        try store.save(conversation)
        let folder = paths.conversationFolder(conversation.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var tracks: [Track] = []
        for kind in source.trackKinds {
            try writeTone(folder.appendingPathComponent(kind.fileName), seconds: 2)
            tracks.append(Track(
                conversationId: conversation.id, kind: kind,
                relativePath: paths.relativeTrackPath(conversation.id, fileName: kind.fileName)
            ))
        }
        try store.saveTracks(tracks)
        return conversation
    }

    private func files(in conversation: Conversation) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: paths.conversationFolder(conversation.id).path)) ?? [])
    }

    func testTwoTracksGetAMixATranscriptAndBecomeProposed() async throws {
        let conversation = try makeConversation()

        let processed = try await processor().process(conversation.id, options: .init())

        XCTAssertEqual(processed.state, .proposed)
        XCTAssertNil(processed.lastError)
        XCTAssertFalse(try store.currentSegments(conversationId: conversation.id).isEmpty)
        XCTAssertFalse(try store.participants(conversationId: conversation.id).isEmpty)
        XCTAssertEqual(try store.currentTranscriptVersion(conversationId: conversation.id)?.conversationId, conversation.id)
        XCTAssertEqual(
            files(in: conversation),
            ["microphone.caf", "system-audio.caf", "mix.caf", "transcript.md"]
        )
        XCTAssertEqual(
            Set(try store.tracks(conversationId: conversation.id).map(\.kind)),
            [.microphone, .system, .mix]
        )
    }

    func testSingleTrackIsUsedAsIs() async throws {
        let conversation = try makeConversation(source: .microphone)
        let processed = try await processor().process(conversation.id, options: .init())
        XCTAssertEqual(processed.state, .proposed)
        XCTAssertEqual(files(in: conversation), ["microphone.caf", "transcript.md"])
    }

    func testFailureKeepsEveryTrackAndRecordsTheError() async throws {
        let conversation = try makeConversation()
        let before = try ["microphone.caf", "system-audio.caf"].map {
            try Data(contentsOf: paths.conversationFolder(conversation.id).appendingPathComponent($0))
        }

        do {
            _ = try await processor(failing: true).process(conversation.id, options: .init())
            XCTFail("processing should fail")
        } catch {}

        let stored = try XCTUnwrap(store.conversation(id: conversation.id))
        XCTAssertEqual(stored.state, .processing)
        XCTAssertEqual(stored.lastError?.contains("simulated ASR failure"), true, stored.lastError ?? "nil")
        let after = try ["microphone.caf", "system-audio.caf"].map {
            try Data(contentsOf: paths.conversationFolder(conversation.id).appendingPathComponent($0))
        }
        XCTAssertEqual(before, after)
        XCTAssertNil(try store.currentTranscriptVersion(conversationId: conversation.id))

        // The same conversation can be processed again once the problem is gone.
        let retried = try await processor().process(conversation.id, options: .init())
        XCTAssertEqual(retried.state, .proposed)
        XCTAssertNil(retried.lastError)
    }

    func testInterruptedConversationCanBeProcessed() async throws {
        let conversation = try makeConversation(state: .interrupted)
        let processed = try await processor().process(conversation.id, options: .init())
        XCTAssertEqual(processed.state, .proposed)
    }

    func testDamagedTrackFallsBackToTheOther() async throws {
        let conversation = try makeConversation(state: .interrupted)
        let folder = paths.conversationFolder(conversation.id)
        try Data("not audio".utf8).write(to: folder.appendingPathComponent("system-audio.caf"))

        let processed = try await processor().process(conversation.id, options: .init())
        XCTAssertEqual(processed.state, .proposed)
        XCTAssertFalse(files(in: conversation).contains("mix.partial.caf"))
    }

    /// An imported conversation has its audio in the old store. Processing it again must read
    /// from there and write only into the conversation's own folder.
    func testImportedConversationLeavesTheOldStoreUntouched() async throws {
        let conversation = Conversation(
            title: "Imported", state: .proposed, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            importedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        try store.save(conversation)
        let legacy = paths.legacySessions.appendingPathComponent(conversation.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        for name in ["microphone.caf", "system-audio.caf"] {
            try writeTone(legacy.appendingPathComponent(name), seconds: 2)
        }
        try store.saveTracks([
            Track(conversationId: conversation.id, kind: .microphone, relativePath: "sessions/\(conversation.id.uuidString)/microphone.caf"),
            Track(conversationId: conversation.id, kind: .system, relativePath: "sessions/\(conversation.id.uuidString)/system-audio.caf"),
        ])

        _ = try await processor().process(conversation.id, options: .init())

        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(atPath: legacy.path)),
            ["microphone.caf", "system-audio.caf"]
        )
        XCTAssertEqual(files(in: conversation), ["mix.caf", "transcript.md"])
        XCTAssertEqual(
            try store.tracks(conversationId: conversation.id).first { $0.kind == .mix }?.relativePath,
            "conversations/\(conversation.id.uuidString)/mix.caf"
        )
    }

    func testNoAudioIsAnErrorNotACrash() async throws {
        let conversation = try makeConversation()
        let folder = paths.conversationFolder(conversation.id)
        for name in ["microphone.caf", "system-audio.caf"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        do {
            _ = try await processor().process(conversation.id, options: .init())
            XCTFail("processing should fail")
        } catch {}
        XCTAssertNotNil(try store.conversation(id: conversation.id)?.lastError)
    }

    func testProcessingAgainDoesNotDuplicateParticipants() async throws {
        let conversation = try makeConversation()
        _ = try await processor().process(conversation.id, options: .init())
        let first = try store.participants(conversationId: conversation.id)
        _ = try await processor().process(conversation.id, options: .init())
        XCTAssertEqual(try store.participants(conversationId: conversation.id), first)
    }

    func testAutomaticExportCarriesTheConversationId() async throws {
        let conversation = try makeConversation()
        let exportFolder = root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        var options = ConversationProcessor.Options()
        options.automaticExport = AutomaticMarkdownExportConfiguration(
            isEnabled: true,
            folderPath: exportFolder.path,
            fileNameTemplate: AutomaticMarkdownExportConfiguration.defaultFileNameTemplate
        )

        _ = try await processor().process(conversation.id, options: options)

        let exported = try FileManager.default.contentsOfDirectory(atPath: exportFolder.path)
        let json = try XCTUnwrap(exported.first { $0.hasSuffix(".json") }, "\(exported)")
        let text = try String(contentsOf: exportFolder.appendingPathComponent(json), encoding: .utf8)
        XCTAssertTrue(text.contains(conversation.id.uuidString), "the envelope must be keyed on the conversation id")
    }
}

final class ProcessingQueueTests: XCTestCase {
    private actor Log {
        var entries: [String] = []
        func add(_ entry: String) { entries.append(entry) }
    }

    func testRunsOneAtATimeInOrder() async {
        let log = Log()
        let ids = [UUID(), UUID(), UUID()]
        let queue = ProcessingQueue { id in
            await log.add("start \(ids.firstIndex(of: id)!)")
            try await Task.sleep(for: .milliseconds(30))
            await log.add("end \(ids.firstIndex(of: id)!)")
        }
        for id in ids { await queue.enqueue(id) }
        await queue.waitUntilIdle()
        let entries = await log.entries
        XCTAssertEqual(entries, ["start 0", "end 0", "start 1", "end 1", "start 2", "end 2"])
    }

    func testQueuingTwiceRunsOnce() async {
        let log = Log()
        let id = UUID()
        let queue = ProcessingQueue { _ in
            await log.add("run")
            try await Task.sleep(for: .milliseconds(30))
        }
        await queue.enqueue(id)
        await queue.enqueue(id)
        await queue.waitUntilIdle()
        let entries = await log.entries
        XCTAssertEqual(entries, ["run"])
    }

    func testAFailureDoesNotStopTheQueueAndIsReported() async {
        let failing = UUID()
        let fine = UUID()
        let queue = ProcessingQueue { id in
            if id == failing { throw LorreError.processingFailed("boom") }
        }
        let events = await queue.events()
        await queue.enqueue(failing)
        await queue.enqueue(fine)

        var seen: [ProcessingQueue.Event] = []
        for await event in events {
            seen.append(event)
            if seen.count == 4 { break }
        }
        XCTAssertEqual(seen.first, .started(failing))
        guard case let .finished(id, error) = seen[1] else { return XCTFail("expected finished") }
        XCTAssertEqual(id, failing)
        XCTAssertEqual(error?.contains("boom"), true)
        XCTAssertEqual(seen[2], .started(fine))
        XCTAssertEqual(seen[3], .finished(fine, error: nil))
    }

    func testIdleQueueReturnsImmediately() async {
        let queue = ProcessingQueue { _ in }
        await queue.waitUntilIdle()
        let waiting = await queue.waiting
        XCTAssertEqual(waiting, [])
    }
}
