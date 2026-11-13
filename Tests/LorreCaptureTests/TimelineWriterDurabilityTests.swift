import AVFoundation
import Foundation
import XCTest
@testable import LorreCapture

final class TimelineWriterDurabilityTests: XCTestCase {
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("writer-\(UUID()).caf")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    private func buffer(seconds: Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * 16_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = 0.25 }
        return buffer
    }

    func testFrameCountIncludesPaddedSilence() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let writer = try TimelineAudioWriter(outputURL: url, format: format)
        writer.setTimelineStart(start)
        writer.write(buffer(seconds: 0.5), at: start.addingTimeInterval(2.5))
        XCTAssertEqual(writer.frameCount, 40_000)
        writer.finish()
        XCTAssertEqual(try AVAudioFile(forReading: url).length, 40_000)
    }

    func testSyncsAtMostOncePerInterval() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let writer = try TimelineAudioWriter(outputURL: url, format: format)
        for step in 0..<25 {
            // 25 buffers of 0.1 s: 2.5 s of audio.
            writer.write(buffer(seconds: 0.1), at: start.addingTimeInterval(Double(step) * 0.1))
        }
        XCTAssertEqual(writer.syncCount, 3, "one sync at the first write, then one per second")
    }

    func testWritesAfterFinishAreIgnored() throws {
        let writer = try TimelineAudioWriter(outputURL: url, format: format)
        writer.write(buffer(seconds: 0.5))
        writer.finish()
        writer.write(buffer(seconds: 0.5))
        writer.finish()
        XCTAssertNil(writer.failureMessage())
        XCTAssertEqual(try AVAudioFile(forReading: url).length, 8_000)
    }

    func testWrongFormatIsReportedNotThrown() throws {
        let writer = try TimelineAudioWriter(outputURL: url, format: format)
        let other = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)!
        let wrong = AVAudioPCMBuffer(pcmFormat: other, frameCapacity: 100)!
        wrong.frameLength = 100
        writer.write(wrong)
        XCTAssertNotNil(writer.failureMessage())
        // After a failure the writer stays quiet instead of failing again on every buffer.
        writer.write(buffer(seconds: 0.1))
        writer.finish()
    }
}
