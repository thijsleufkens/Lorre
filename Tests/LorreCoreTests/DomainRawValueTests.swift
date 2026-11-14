import XCTest
@testable import LorreCore

/// Raw values are stored in the database and exported in records. A failing test here means a
/// rename that needs a migration, not a test to update.
final class DomainRawValueTests: XCTestCase {
    func testConversationType() {
        XCTAssertEqual(ConversationType.allCases.map(\.rawValue), ["workMeeting", "intake", "network", "other"])
    }

    func testConversationState() {
        XCTAssertEqual(
            ConversationState.allCases.map(\.rawValue),
            ["recording", "interrupted", "processing", "proposed", "approved", "changed"]
        )
    }

    func testTrackKind() {
        XCTAssertEqual(TrackKind.allCases.map(\.rawValue), ["mix", "microphone", "system", "device"])
    }

    func testCaptureSource() {
        XCTAssertEqual(
            CaptureSource.allCases.map(\.rawValue),
            ["microphone", "systemAudio", "microphoneAndSystemAudio"]
        )
    }

    func testOutcomeKind() {
        XCTAssertEqual(
            OutcomeKind.allCases.map(\.rawValue),
            ["decision", "myAction", "theirCommitment", "openPoint", "information", "followUpHook", "personNote"]
        )
    }

    func testOutcomeStatusAndSource() {
        XCTAssertEqual(OutcomeStatus.allCases.map(\.rawValue), ["proposed", "approved", "rejected"])
        XCTAssertEqual(OutcomeSource.allCases.map(\.rawValue), ["model", "user", "agent"])
    }

    func testRecordStatus() {
        XCTAssertEqual(RecordStatus.allCases.map(\.rawValue), ["draft", "approved"])
    }
}
