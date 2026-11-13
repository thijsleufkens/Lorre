#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// Writes a tone through `TimelineAudioWriter` in real time and never closes the file.
/// Used to check what a killed process leaves on disk.
public enum WriterSelfTest {
    public static let sampleRate: Double = 48_000
    public static let amplitude: Float = 0.5

    public static func run(output: URL, seconds: Double) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        ) else { throw CaptureError.startFailed("Could not create the test format.") }
        let writer = try TimelineAudioWriter(outputURL: output, format: format)
        let start = Date()
        writer.setTimelineStart(start)

        let framesPerBuffer = AVAudioFrameCount(sampleRate / 10)
        var phase = 0.0
        while Date().timeIntervalSince(start) < seconds {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerBuffer),
                  let channel = buffer.floatChannelData?[0] else { break }
            buffer.frameLength = framesPerBuffer
            for frame in 0..<Int(framesPerBuffer) {
                channel[frame] = amplitude * Float(sin(phase))
                phase += 2 * .pi * 440 / sampleRate
            }
            writer.write(buffer)
            Thread.sleep(forTimeInterval: 0.1)
        }
        // Deliberately not finished: the caller is expected to be killed first.
        Thread.sleep(forTimeInterval: 3600)
    }
}
#endif
