import Foundation
import XCTest
@testable import Lorre

/// Session store that fails `createSession`, simulating a full disk or a
/// permissions problem at the moment the user stops a recording.
private struct FailingCreateSessionStore: SessionStore {
    let backing: FileSessionStore

    func loadSessions() async throws -> [SessionManifest] { try await backing.loadSessions() }
    func loadSession(id: UUID) async throws -> SessionManifest? { try await backing.loadSession(id: id) }
    func createSession(_ draft: NewSessionDraft) async throws -> SessionManifest {
        throw LorreError.persistenceFailed("Simulated createSession failure")
    }
    func updateSession(_ session: SessionManifest) async throws { try await backing.updateSession(session) }
    func deleteSession(id: UUID) async throws { try await backing.deleteSession(id: id) }
    func loadTranscript(sessionId: UUID) async throws -> TranscriptDocument? { try await backing.loadTranscript(sessionId: sessionId) }
    func saveTranscript(_ transcript: TranscriptDocument) async throws { try await backing.saveTranscript(transcript) }
    func sessionDirectoryURL(for sessionId: UUID) async -> URL { await backing.sessionDirectoryURL(for: sessionId) }
    func exportDirectoryURL(for sessionId: UUID) async -> URL { await backing.exportDirectoryURL(for: sessionId) }
}

final class RecorderLifecycleTests: XCTestCase {
    func testStopFailureTearsDownCaptureAndAllowsNewRecording() async throws {
        let root = makeTemporaryRoot(named: "recorder-lifecycle")
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = ControlledRecorderService()
        let dependencies = makeTestDependencies(
            root: root,
            store: FailingCreateSessionStore(backing: FileSessionStore(baseURL: root)),
            recorder: recorder
        )

        let viewModel = await MainActor.run { AppViewModel(dependencies: dependencies) }
        await viewModel.start()

        await MainActor.run { viewModel.startRecordingTapped() }
        try await waitUntil {
            await MainActor.run { viewModel.isRecording }
        }

        await MainActor.run { viewModel.stopRecordingTapped() }
        try await waitUntil {
            await MainActor.run { !viewModel.isRecording && !viewModel.isStoppingRecording }
        }

        let stillCapturing = await recorder.isCapturing()
        XCTAssertFalse(
            stillCapturing,
            "A failed stop must tear down the live capture, not leave the mic/tap running"
        )

        // The recorder must accept a fresh recording after the failed stop.
        await MainActor.run { viewModel.startRecordingTapped() }
        try await waitUntil {
            await MainActor.run { viewModel.isRecording }
        }
        let startCallCount = await recorder.startCallCount
        XCTAssertEqual(startCallCount, 2)
    }
}
