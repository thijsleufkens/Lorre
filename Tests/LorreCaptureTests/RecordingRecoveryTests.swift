import Foundation
import XCTest
@testable import LorreCapture
@testable import LorreCore

final class RecordingRecoveryTests: XCTestCase {
    private var root: URL!
    private var paths: LorrePaths!
    private var database: LorreDatabase!
    private var store: ConversationStore!

    override func setUpWithError() throws {
        root = makeTemporaryRoot(named: "recovery")
        paths = LorrePaths(root: root)
        database = try LorreDatabase(url: paths.database)
        store = ConversationStore(database: database)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func recover() throws -> RecoveryReport {
        try RecordingRecovery(paths: paths, database: database).run()
    }

    @discardableResult
    private func makeRecording(
        state: ConversationState = .recording,
        microphoneSeconds: Double? = 1,
        systemSeconds: Double? = 2
    ) throws -> Conversation {
        let conversation = Conversation(
            title: "Test", state: state, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            captureSource: .microphoneAndSystemAudio
        )
        try store.save(conversation)
        let folder = paths.conversationFolder(conversation.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let microphoneSeconds { try writeTone(to: folder.appendingPathComponent("microphone.caf"), seconds: microphoneSeconds) }
        if let systemSeconds { try writeTone(to: folder.appendingPathComponent("system-audio.caf"), seconds: systemSeconds) }
        return conversation
    }

    private func deadPID() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }

    func testStaleLockBecomesInterruptedWithDurationFromTheLongestTrack() throws {
        let conversation = try makeRecording()
        let folder = paths.conversationFolder(conversation.id)
        try RecordingLock.write(in: folder, pid: try deadPID())

        let report = try recover()

        XCTAssertEqual(report.recovered, [conversation.id])
        XCTAssertTrue(report.foundInterruptedRecordings)
        let stored = try XCTUnwrap(store.conversation(id: conversation.id))
        XCTAssertEqual(stored.state, .interrupted)
        XCTAssertEqual(try XCTUnwrap(stored.durationSeconds), 2, accuracy: 0.05)
        XCTAssertNotNil(stored.lastError)
        XCTAssertNil(RecordingLock.pid(in: folder))
    }

    func testLiveLockIsLeftAlone() throws {
        let conversation = try makeRecording()
        try RecordingLock.write(in: paths.conversationFolder(conversation.id))

        let report = try recover()

        XCTAssertEqual(report.stillLive, [conversation.id])
        XCTAssertEqual(report.recovered, [])
        XCTAssertEqual(try store.conversation(id: conversation.id)?.state, .recording)
        XCTAssertTrue(RecordingLock.isLive(in: paths.conversationFolder(conversation.id)))
    }

    func testNoLockAtAllBecomesInterrupted() throws {
        let conversation = try makeRecording()
        XCTAssertEqual(try recover().recovered, [conversation.id])
    }

    func testOrphanFolderWithAudioIsAdopted() throws {
        let id = UUID()
        let folder = paths.conversationFolder(id)
        try writeTone(to: folder.appendingPathComponent("microphone.caf"), seconds: 1.5)

        let report = try recover()

        XCTAssertEqual(report.adopted, [id])
        let stored = try XCTUnwrap(store.conversation(id: id))
        XCTAssertEqual(stored.state, .interrupted)
        XCTAssertEqual(stored.captureSource, .microphone)
        XCTAssertEqual(try XCTUnwrap(stored.durationSeconds), 1.5, accuracy: 0.05)
        XCTAssertEqual(
            try store.tracks(conversationId: id).map(\.relativePath),
            ["conversations/\(id.uuidString)/microphone.caf"]
        )
    }

    func testFoldersWithoutAudioOrWithOtherNamesAreIgnored() throws {
        try FileManager.default.createDirectory(at: paths.conversationFolder(UUID()), withIntermediateDirectories: true)
        try writeTone(to: paths.conversations.appendingPathComponent("not-a-uuid/microphone.caf"), seconds: 1)
        let emptyTrack = paths.conversationFolder(UUID()).appendingPathComponent("microphone.caf")
        try FileManager.default.createDirectory(at: emptyTrack.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: emptyTrack)

        let report = try recover()
        XCTAssertEqual(report.adopted, [])
        XCTAssertEqual(try store.listConversations().count, 0)
    }

    func testUnreadableTrackDoesNotStopRecoveryOfTheOther() throws {
        let conversation = try makeRecording(microphoneSeconds: nil, systemSeconds: 3)
        let folder = paths.conversationFolder(conversation.id)
        try Data("this is not audio".utf8).write(to: folder.appendingPathComponent("microphone.caf"))

        XCTAssertEqual(try recover().recovered, [conversation.id])
        let stored = try XCTUnwrap(store.conversation(id: conversation.id))
        XCTAssertEqual(try XCTUnwrap(stored.durationSeconds), 3, accuracy: 0.05)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("microphone.caf").path))
    }

    func testRecordingWithoutAnyReadableAudioIsStillRecovered() throws {
        let conversation = try makeRecording(microphoneSeconds: nil, systemSeconds: nil)
        XCTAssertEqual(try recover().recovered, [conversation.id])
        XCTAssertNil(try store.conversation(id: conversation.id)?.durationSeconds)
    }

    func testProcessingConversationsAreRequeued() throws {
        let waiting = try makeRecording(state: .processing)
        try makeRecording(state: .proposed)
        let report = try recover()
        XCTAssertEqual(report.requeue, [waiting.id])
        XCTAssertFalse(report.foundInterruptedRecordings)
    }

    func testSecondRunChangesNothing() throws {
        try makeRecording()
        try writeTone(to: paths.conversationFolder(UUID()).appendingPathComponent("system-audio.caf"), seconds: 1)
        let first = try recover()
        XCTAssertEqual(first.recovered.count + first.adopted.count, 2)

        let before = try store.listConversations()
        let second = try recover()
        XCTAssertEqual(second, RecoveryReport())
        XCTAssertEqual(try store.listConversations(), before)
    }

    func testRecoveryNeverTouchesAudio() throws {
        let conversation = try makeRecording()
        let folder = paths.conversationFolder(conversation.id)
        let before = try ["microphone.caf", "system-audio.caf"].map {
            try Data(contentsOf: folder.appendingPathComponent($0))
        }
        _ = try recover()
        let after = try ["microphone.caf", "system-audio.caf"].map {
            try Data(contentsOf: folder.appendingPathComponent($0))
        }
        XCTAssertEqual(before, after)
    }
}
