import AVFoundation
import Foundation
import XCTest
@testable import Lorre

/// The process tap only delivers buffers while a listed process is actually
/// producing audio: a recording that starts in silence gets its first
/// callback minutes in, and the stem would start at t=0 of *that* moment —
/// shifted against the microphone stem. The writer therefore tracks the
/// recording timeline and pads gaps with silence.
final class ProcessTapWriterTimelineTests: XCTestCase {
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false
    )!

    private func makeBuffer(seconds: Double, value: Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * 48_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            for i in 0..<Int(frames) { buffer.floatChannelData![channel][i] = value }
        }
        return buffer
    }

    private func readMono(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        var samples: [Float] = []
        while file.framePosition < file.length {
            let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65536)!
            try file.read(into: buf)
            guard buf.frameLength > 0 else { break }
            samples.append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
        }
        return samples
    }

    func testLateFirstCallbackGetsLeadingSilencePadding() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tap-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let start = Date(timeIntervalSince1970: 1_000)
        let writer = try ProcessTapAudioWriter(outputURL: url, format: format)
        writer.setTimelineStart(start)

        // First audio arrives 5 seconds into the recording (0.5s buffer
        // delivered at t=5.5, covering 5.0–5.5).
        writer.write(makeBuffer(seconds: 0.5, value: 0.4), at: start.addingTimeInterval(5.5))
        writer.finish()

        let samples = try readMono(url)
        XCTAssertEqual(Double(samples.count) / 48_000, 5.5, accuracy: 0.1, "Stem must span the full recording timeline")
        XCTAssertEqual(samples[Int(2.0 * 48_000)], 0, "The pre-audio span must be silence")
        XCTAssertEqual(samples[Int(5.25 * 48_000)], 0.4, accuracy: 0.001, "The delivered audio must sit at its wall-clock position")
    }

    func testContinuousDeliveryIsNotPadded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tap-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let start = Date(timeIntervalSince1970: 1_000)
        let writer = try ProcessTapAudioWriter(outputURL: url, format: format)
        writer.setTimelineStart(start)

        // Steady 0.25s buffers arriving on cadence (with a realistic ±0.1s
        // delivery jitter) must not trigger any padding.
        for i in 0..<8 {
            let at = start.addingTimeInterval(Double(i + 1) * 0.25 + (i % 2 == 0 ? 0.08 : -0.05))
            writer.write(makeBuffer(seconds: 0.25, value: 0.3), at: at)
        }
        writer.finish()

        let samples = try readMono(url)
        XCTAssertEqual(samples.count, 8 * 12_000, "No silence may be inserted between on-cadence buffers")
        XCTAssertEqual(samples[60_000], 0.3, accuracy: 0.001)
    }

    func testMidRecordingGapIsPadded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tap-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let start = Date(timeIntervalSince1970: 1_000)
        let writer = try ProcessTapAudioWriter(outputURL: url, format: format)
        writer.setTimelineStart(start)

        writer.write(makeBuffer(seconds: 0.5, value: 0.3), at: start.addingTimeInterval(0.5))
        // YouTube paused for ~3 seconds; next buffer arrives at t=4.0.
        writer.write(makeBuffer(seconds: 0.5, value: 0.5), at: start.addingTimeInterval(4.0))
        writer.finish()

        let samples = try readMono(url)
        XCTAssertEqual(Double(samples.count) / 48_000, 4.0, accuracy: 0.1)
        XCTAssertEqual(samples[Int(2.0 * 48_000)], 0, "The pause must be silence")
        XCTAssertEqual(samples[Int(3.8 * 48_000)], 0.5, accuracy: 0.001, "Audio after the pause must sit at its wall-clock position")
    }
}
