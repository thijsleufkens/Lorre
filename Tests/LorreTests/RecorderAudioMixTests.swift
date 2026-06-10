import AVFoundation
import Foundation
import XCTest
@testable import Lorre

/// Characterization tests for `mixToCanonicalFile` — they pin the mixing
/// contract (gains, padding, global peak normalization, resampling) so the
/// implementation can stream chunk-wise instead of loading whole stems
/// into memory.
final class RecorderAudioMixTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = makeTemporaryRoot(named: "audio-mix")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func writeInput(_ samples: [Float], named name: String, format: AVAudioFormat) throws -> URL {
        let url = root.appendingPathComponent(name)
        try RecorderAudioUtilities.write(samples: samples, to: url, format: format)
        return url
    }

    /// Reads the canonical file directly (it is written in `previewFormat`,
    /// so no conversion is involved in the measurement). Reads in a loop:
    /// a single `AVAudioFile.read(into:)` may return fewer frames than
    /// requested, even mid-file.
    private func readSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        var samples: [Float] = []
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else {
                throw LorreError.persistenceFailed("Could not allocate read buffer")
            }
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channelData = buffer.floatChannelData else { break }
            samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
        }
        return samples
    }

    func testMixesWithEqualGainsAndPadsShorterStem() throws {
        let format = RecorderAudioUtilities.previewFormat
        let mic = try writeInput([Float](repeating: 0.5, count: 1000), named: "mic.caf", format: format)
        let sys = try writeInput([Float](repeating: 0.25, count: 400), named: "sys.caf", format: format)
        let destination = root.appendingPathComponent("mix.caf")

        try RecorderAudioUtilities.mixToCanonicalFile(
            microphoneURL: mic, systemAudioURL: sys, destinationURL: destination
        )

        let mixed = try readSamples(destination)
        XCTAssertEqual(mixed.count, 1000, "Output length must be the longest stem")

        let bothExpected: Float = ((0.5 * 0.70710677) + (0.25 * 0.70710677)) * 0.8
        let micOnlyExpected: Float = (0.5 * 0.70710677) * 0.8
        XCTAssertEqual(mixed[100], bothExpected, accuracy: 0.001)
        XCTAssertEqual(mixed[800], micOnlyExpected, accuracy: 0.001, "Past the shorter stem only the longer one contributes")
    }

    func testGlobalPeakNormalizationScalesEntireMix() throws {
        let format = RecorderAudioUtilities.previewFormat
        // Loud head, quiet tail: global normalization must scale BOTH by the
        // same factor (per-sample clipping would leave the tail untouched).
        let loudHead = [Float](repeating: 0.95, count: 200)
        let quietTail = [Float](repeating: 0.1, count: 200)
        let mic = try writeInput(loudHead + quietTail, named: "mic.caf", format: format)
        let sys = try writeInput(loudHead + quietTail, named: "sys.caf", format: format)
        let destination = root.appendingPathComponent("mix.caf")

        try RecorderAudioUtilities.mixToCanonicalFile(
            microphoneURL: mic, systemAudioURL: sys, destinationURL: destination
        )

        let mixed = try readSamples(destination)
        let rawPeak: Float = ((0.95 * 0.70710677) * 2) * 0.8 // ≈ 1.074 > 0.98 ⇒ normalize
        let gain = 0.98 / rawPeak
        XCTAssertEqual(mixed.max() ?? 0, 0.98, accuracy: 0.002)
        let expectedTail: Float = ((0.1 * 0.70710677) * 2) * 0.8 * gain
        XCTAssertEqual(mixed[300], expectedTail, accuracy: 0.002)
    }

    func testEmptyStemsProduceEmptyCanonicalFile() throws {
        let format = RecorderAudioUtilities.previewFormat
        let mic = try writeInput([], named: "mic.caf", format: format)
        let sys = try writeInput([], named: "sys.caf", format: format)
        let destination = root.appendingPathComponent("mix.caf")

        try RecorderAudioUtilities.mixToCanonicalFile(
            microphoneURL: mic, systemAudioURL: sys, destinationURL: destination
        )

        XCTAssertEqual(try readSamples(destination).count, 0)
    }

    func testResamplesStereo48kInputs() throws {
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false
        )!
        let mic = try writeInput([Float](repeating: 0.4, count: 48_000), named: "mic48.caf", format: inputFormat)
        let sys = try writeInput([Float](repeating: 0.2, count: 48_000), named: "sys48.caf", format: inputFormat)
        let destination = root.appendingPathComponent("mix.caf")

        try RecorderAudioUtilities.mixToCanonicalFile(
            microphoneURL: mic, systemAudioURL: sys, destinationURL: destination
        )

        let mixed = try readSamples(destination)
        // 1s of 48 kHz input → ~1s of 16 kHz output.
        XCTAssertEqual(Double(mixed.count), 16_000, accuracy: 200)
        let expected: Float = ((0.4 * 0.70710677) + (0.2 * 0.70710677)) * 0.8
        XCTAssertEqual(mixed[8000], expected, accuracy: 0.01)
    }
}
