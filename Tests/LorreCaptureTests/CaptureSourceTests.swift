import AVFoundation
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

    func testPeakOfABuffer() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        XCTAssertEqual(buffer.lorre_peak(), 0, "a buffer of zeros is digital silence")
        buffer.floatChannelData![0][2] = -0.25
        XCTAssertEqual(buffer.lorre_peak(), 0.25)
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
