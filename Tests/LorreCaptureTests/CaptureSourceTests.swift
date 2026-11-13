import XCTest
@testable import LorreCapture
@testable import LorreCore

final class CaptureSourceTests: XCTestCase {
    func testTracksPerSource() {
        XCTAssertEqual(CaptureSource.microphone.trackKinds, [.microphone])
        XCTAssertEqual(CaptureSource.systemAudio.trackKinds, [.system])
        XCTAssertEqual(CaptureSource.microphoneAndSystemAudio.trackKinds, [.microphone, .system])
    }

    func testTrackFileNames() {
        XCTAssertEqual(TrackKind.microphone.fileName, "microphone.caf")
        XCTAssertEqual(TrackKind.system.fileName, "system-audio.caf")
        XCTAssertEqual(TrackKind.mix.fileName, "mix.caf")
    }

    func testSleepGuardBalances() {
        let sleepGuard = SleepGuard()
        XCTAssertFalse(sleepGuard.isActive)
        sleepGuard.begin()
        sleepGuard.begin()
        XCTAssertTrue(sleepGuard.isActive)
        sleepGuard.end()
        XCTAssertFalse(sleepGuard.isActive)
        sleepGuard.end()
    }
}
