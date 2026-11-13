#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// Writes incoming PCM buffers to a `.caf` file on the recording's timeline.
///
/// Every track of a recording goes through this writer with the same anchor, so the files stay
/// aligned with each other: silence is written for any stretch in which no audio was delivered.
///
/// What has been written is pushed to disk about once a second, which bounds what a power loss
/// can cost. A file that was never closed (crash, force-quit) remains readable.
///
/// Thread safety: `write(_:)` and `finish()` may be called from different
/// queues (IO proc queue vs stop path). An `NSLock` guards the file write.
@available(macOS 15.0, *)
public final class TimelineAudioWriter: @unchecked Sendable {
    private var file: AVAudioFile?
    private let format: AVAudioFormat
    private let syncHandle: FileHandle?
    private var lastSync: Date?
    private(set) var syncCount = 0

    /// How often written audio is forced to disk.
    static let syncInterval: TimeInterval = 1
    private let lock = NSLock()
    private var writeFailureMessage: String?
    private var timelineStart: Date?
    private var framesWritten: Int64 = 0

    /// The tap delivers buffers only while a listed process is actually
    /// producing audio. Gaps larger than this are filled with silence so the
    /// stem stays aligned to the recording's wall-clock timeline; smaller
    /// deviations are normal callback jitter and are left alone.
    private let gapThresholdSeconds = 0.35

    public init(outputURL: URL, format: AVAudioFormat) throws {
        self.file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        self.format = format
        // AVAudioFile has no way to force its data to disk; a second handle on the same file does.
        self.syncHandle = try? FileHandle(forWritingTo: outputURL)
    }

    /// Frames written so far, silence included.
    public var frameCount: Int64 {
        lock.withLock { framesWritten }
    }

    /// Anchors the stem's timeline. Use the moment the recording started
    /// (the mic capture start in mic+system mode), so all stems share t=0.
    public func setTimelineStart(_ date: Date) {
        lock.withLock { timelineStart = date }
    }

    public func write(_ buffer: AVAudioPCMBuffer) {
        write(buffer, at: Date())
    }

    public func write(_ buffer: AVAudioPCMBuffer, at callbackDate: Date) {
        lock.withLock {
            guard writeFailureMessage == nil, let file else { return }
            do {
                if let timelineStart {
                    // The buffer delivered at `callbackDate` covers the time
                    // span just before it; everything missing in between was
                    // a delivery gap (no process producing audio).
                    let elapsed = callbackDate.timeIntervalSince(timelineStart)
                    let expectedBefore = Int64((elapsed * format.sampleRate).rounded()) - Int64(buffer.frameLength)
                    let gapFrames = expectedBefore - framesWritten
                    if Double(gapFrames) / format.sampleRate > gapThresholdSeconds {
                        try writeSilence(frames: gapFrames, to: file)
                    }
                }
                try file.write(from: buffer)
                framesWritten += Int64(buffer.frameLength)
                syncIfDue(at: callbackDate)
            } catch {
                writeFailureMessage = error.localizedDescription
            }
        }
    }

    /// Called with the lock held.
    private func syncIfDue(at date: Date) {
        if let lastSync, date.timeIntervalSince(lastSync) < Self.syncInterval { return }
        lastSync = date
        guard let syncHandle else { return }
        try? syncHandle.synchronize()
        syncCount += 1
    }

    private func writeSilence(frames: Int64, to file: AVAudioFile) throws {
        var remaining = frames
        while remaining > 0 {
            let chunk = AVAudioFrameCount(min(remaining, 48_000))
            guard let silent = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
            silent.frameLength = chunk
            if let channels = silent.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    channels[channel].update(repeating: 0, count: Int(chunk))
                }
            }
            try file.write(from: silent)
            framesWritten += Int64(chunk)
            remaining -= Int64(chunk)
        }
    }

    public func failureMessage() -> String? {
        lock.withLock { writeFailureMessage }
    }

    /// Closes the file. Later writes are ignored. Safe to call more than once.
    public func finish() {
        lock.withLock {
            file?.close()
            file = nil
            try? syncHandle?.synchronize()
            try? syncHandle?.close()
        }
    }
}

/// The name this writer had while only the Process Tap used it.
@available(macOS 15.0, *)
public typealias ProcessTapAudioWriter = TimelineAudioWriter
#endif
