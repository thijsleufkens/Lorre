import Foundation
import XCTest
@testable import Lorre

/// Transcription service whose `transcribe` runs an injected hook, so tests can
/// simulate user actions (rename, delete) happening while processing is mid-flight.
private struct HookedTranscriptionService: TranscriptionService {
    var onTranscribe: @Sendable () async throws -> Void = {}

    func ensureModelsReady(
        onProgress: (@Sendable (ProcessingUpdate) async -> Void)?
    ) async throws {}

    func setVocabularyBoostingConfiguration(_ configuration: VocabularyBoostingConfiguration) async {}

    func setBatchTranscriptionLanguage(_ language: BatchTranscriptionLanguage) async {}

    func transcribe(url: URL, sessionTitle: String, source: RecordingSource) async throws -> TranscriptionResult {
        try await onTranscribe()
        return TranscriptionResult(
            engineName: "HookedMock",
            utterances: [TranscriptionUtterance(startMs: 0, endMs: 1200, text: "Hallo daar.", confidence: 0.9)]
        )
    }
}

final class ProcessingLifecycleTests: XCTestCase {
    private var root: URL!
    private var store: FileSessionStore!

    override func setUp() {
        super.setUp()
        root = makeTemporaryRoot(named: "processing-lifecycle")
        store = FileSessionStore(baseURL: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeSession(title: String = "Test sessie") async throws -> SessionManifest {
        try await store.createSession(
            NewSessionDraft(
                title: title,
                folderId: nil,
                status: .processing,
                durationSeconds: 10,
                recordingSource: .microphone,
                audioFileName: "audio.caf",
                microphoneStemFileName: nil,
                systemAudioStemFileName: nil,
                recordedAt: Date()
            )
        )
    }

    private func sessionDirectory(for id: UUID) async -> URL {
        await store.sessionDirectoryURL(for: id)
    }

    // MARK: - FileSessionStore: update must not recreate a deleted session

    func testUpdateSessionThrowsForDeletedSessionAndDoesNotRecreateDirectory() async throws {
        let session = try await makeSession()
        try await store.deleteSession(id: session.id)

        var mutated = session
        mutated.title = "Zombie"

        do {
            try await store.updateSession(mutated)
            XCTFail("updateSession should throw for a deleted session")
        } catch {
            // expected
        }

        let dir = await sessionDirectory(for: session.id)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)),
            "updateSession must not recreate the deleted session directory"
        )
    }

    func testSaveTranscriptThrowsForDeletedSessionAndDoesNotRecreateDirectory() async throws {
        let session = try await makeSession()
        try await store.deleteSession(id: session.id)

        let transcript = TranscriptDocument(
            sessionId: session.id,
            sourceEngine: "HookedMock",
            segments: [],
            speakers: []
        )

        do {
            try await store.saveTranscript(transcript)
            XCTFail("saveTranscript should throw for a deleted session")
        } catch {
            // expected
        }

        let dir = await sessionDirectory(for: session.id)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)),
            "saveTranscript must not recreate the deleted session directory"
        )
    }

    // MARK: - ProcessingCoordinator: concurrent edits must survive processing

    func testProcessingPreservesConcurrentTitleAndNotesEdit() async throws {
        let session = try await makeSession(title: "Originele titel")
        let store = self.store!

        let transcription = HookedTranscriptionService(onTranscribe: {
            // Simulate the user renaming the session while ASR is running.
            guard var latest = try await store.loadSession(id: session.id) else {
                XCTFail("Session disappeared mid-test")
                return
            }
            latest.title = "Hernoemd tijdens verwerking"
            latest.notes = "Notitie tijdens verwerking"
            latest.updatedAt = Date()
            try await store.updateSession(latest)
        })

        let coordinator = ProcessingCoordinator(
            store: store,
            transcriptionService: transcription,
            diarizationService: MockSpeakerDiarizationService()
        )

        _ = try await coordinator.process(sessionId: session.id, enableDiarization: false) { _ in }

        let final = try await store.loadSession(id: session.id)
        XCTAssertEqual(final?.title, "Hernoemd tijdens verwerking", "Processing must not revert a concurrent rename")
        XCTAssertEqual(final?.notes, "Notitie tijdens verwerking", "Processing must not revert concurrent notes edits")
        XCTAssertEqual(final?.status, .ready)
    }

    // MARK: - ProcessingCoordinator: deletion mid-processing must not resurrect

    func testProcessingAfterDeleteDoesNotResurrectSessionDirectory() async throws {
        let session = try await makeSession()
        let store = self.store!

        let transcription = HookedTranscriptionService(onTranscribe: {
            // Simulate the user deleting the session while ASR is running.
            try await store.deleteSession(id: session.id)
        })

        let coordinator = ProcessingCoordinator(
            store: store,
            transcriptionService: transcription,
            diarizationService: MockSpeakerDiarizationService()
        )

        do {
            _ = try await coordinator.process(sessionId: session.id, enableDiarization: false) { _ in }
            XCTFail("Processing a deleted session should not complete normally")
        } catch is CancellationError {
            // expected: deletion mid-flight is treated as cancellation
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let dir = await sessionDirectory(for: session.id)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)),
            "Processing must not recreate the deleted session directory"
        )
    }
}
