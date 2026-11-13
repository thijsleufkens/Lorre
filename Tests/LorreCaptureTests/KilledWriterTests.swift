import AVFoundation
import Foundation
import XCTest
@testable import LorreCapture

/// Recovery rests on one assumption: audio written by a process that was killed, and so never
/// closed its file, can still be read. This test kills a real process to check it.
final class KilledWriterTests: XCTestCase {
    private func lorreBinary() -> URL? {
        // The executable is built into the same products folder as the test bundle.
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let candidate = products.appendingPathComponent("Lorre")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    func testAudioSurvivesSIGKILL() throws {
        guard let binary = lorreBinary() else {
            throw XCTSkip("Lorre executable not found next to the test bundle")
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("killed-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["capture-selftest", "--out", output.path, "--seconds", "60"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        Thread.sleep(forTimeInterval: 4)
        XCTAssertTrue(process.isRunning, "the self-test should still be writing")
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)

        let duration = try XCTUnwrap(RecordingRecovery.trackDuration(output), "the killed file must be readable")
        // Written for about 4 s; allow for process start-up and the last unflushed stretch.
        XCTAssertGreaterThan(duration, 2.0, "readable audio after kill: \(duration) s")

        let file = try AVAudioFile(forReading: output)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 48_000))
        try file.read(into: buffer)
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        let peak = samples.map(abs).max() ?? 0
        XCTAssertEqual(peak, WriterSelfTest.amplitude, accuracy: 0.02, "the audio itself must be intact")
        print("KilledWriterTests: \(String(format: "%.2f", duration)) s readable after SIGKILL at ~4 s")
    }
}
