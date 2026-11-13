import AVFoundation
import Foundation
import XCTest
@testable import LorreCapture
@testable import LorreCore

func makeTemporaryRoot(named prefix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
}

/// Writes a short real `.caf` file, so code that reads durations has something to read.
func writeTone(to url: URL, seconds: Double, sampleRate: Double = 16_000) throws {
    let format = try XCTUnwrap(AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
    ))
    let samples = (0..<Int(seconds * sampleRate)).map { Float(sin(Double($0) * 0.05)) * 0.5 }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try RecorderAudioUtilities.write(samples: samples, to: url, format: format)
}

/// A capture engine that writes fixed files instead of recording.
actor FakeCaptureEngine: CaptureEngine {
    var startError: CaptureError?
    var trackFailures: [TrackKind: String] = [:]
    /// Seconds of audio to put in each track at start; 0 writes an empty file, nil writes no file.
    var seconds: [TrackKind: Double?] = [.microphone: 1, .system: 1]
    var duration: Double = 42
    private(set) var isRunning = false
    private(set) var startCount = 0

    func set(startError: CaptureError?) { self.startError = startError }
    func set(trackFailures: [TrackKind: String]) { self.trackFailures = trackFailures }
    func set(seconds: [TrackKind: Double?]) { self.seconds = seconds }

    func start(source: CaptureSource, into folder: URL) async throws -> CaptureStart {
        startCount += 1
        if let startError { throw startError }
        for kind in source.trackKinds {
            let url = folder.appendingPathComponent(kind.fileName)
            switch seconds[kind] ?? nil {
            case let .some(length) where length > 0: try writeTone(to: url, seconds: length)
            case .some: try Data().write(to: url)
            case .none: break
            }
        }
        isRunning = true
        return CaptureStart(startedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    func stop() async -> CaptureStop {
        isRunning = false
        return CaptureStop(
            endedAt: Date(timeIntervalSince1970: 1_800_000_000 + duration),
            durationSeconds: duration,
            trackFailures: trackFailures
        )
    }

    func levels() async -> [TrackKind: Double] { [:] }
}
