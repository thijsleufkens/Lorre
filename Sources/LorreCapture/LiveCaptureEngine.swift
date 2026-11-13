#if canImport(AVFoundation)
import AVFoundation
import Foundation
import LorreCore
import os

/// Records the microphone and/or system audio into a conversation folder.
///
/// The microphone path carries over what was learned the hard way about voice processing
/// (see the comments below and CLAUDE.md); system audio is the Process Tap capture unchanged.
public actor LiveCaptureEngine: CaptureEngine {
    private final class MeterBox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [TrackKind: Double] = [:]

        func set(_ level: Double, for kind: TrackKind) {
            lock.withLock { values[kind] = level }
        }

        func snapshot() -> [TrackKind: Double] {
            lock.withLock { values }
        }

        func reset() {
            lock.withLock {
                values = [:]
                peaks = [:]
            }
        }

        private var peaks: [TrackKind: Float] = [:]

        /// Remembers the loudest sample seen on a track since the recording started.
        func notePeak(_ peak: Float, for kind: TrackKind) {
            lock.withLock { peaks[kind] = max(peaks[kind] ?? 0, peak) }
        }

        func peak(for kind: TrackKind) -> Float? {
            lock.withLock { peaks[kind] }
        }
    }

    /// A working microphone never delivers exact zeros for this long; even a quiet room has noise.
    static let silenceVerdictDelay: TimeInterval = 3

    private let logger = Logger(subsystem: "lorre", category: "Capture")
    private let meters = MeterBox()
    private let sleepGuard = SleepGuard()

    private var source: CaptureSource?
    private var startedAt: Date?
    private var microphoneEngine: AVAudioEngine?
    private var microphoneWriter: TimelineAudioWriter?
    private var microphoneFileFormat: AVAudioFormat?
    private var configurationObserver: NSObjectProtocol?
    private var systemCapture: ProcessTapSystemAudioCapture?

    public init() {}

    public func start(source: CaptureSource, into folder: URL) async throws -> CaptureStart {
        guard self.source == nil else { throw CaptureError.alreadyRecording }
        try await Self.ensureMicrophonePermission()

        let microphoneURL = folder.appendingPathComponent(TrackKind.microphone.fileName)
        let systemURL = folder.appendingPathComponent(TrackKind.system.fileName)

        do {
            var microphoneStartedAt: Date?
            if source.includesMicrophone {
                microphoneStartedAt = try startMicrophone(writingTo: microphoneURL, source: source)
            }
            if source.includesSystemAudio {
                let tap = ProcessTapSystemAudioCapture()
                let meters = self.meters
                _ = try await tap.start(
                    outputURL: systemURL,
                    // The microphone engine already keeps the audio system awake; a second engine
                    // can cause monitoring feedback.
                    outputWarmerRequired: !source.includesMicrophone,
                    // Both tracks share the microphone's start as t=0.
                    timelineStart: microphoneStartedAt,
                    onPCMBuffer: { _ in },
                    onMeterLevel: { meters.set($0, for: .system) }
                )
                systemCapture = tap
            }
            let startedAt = microphoneStartedAt ?? Date()
            self.source = source
            self.startedAt = startedAt
            sleepGuard.begin()
            return CaptureStart(startedAt: startedAt)
        } catch {
            // All or nothing: nothing worth keeping has been captured at this point.
            tearDown()
            for url in [microphoneURL, systemURL] {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }
    }

    public func stop() async -> CaptureStop {
        let endedAt = Date()
        let duration = startedAt.map { max(endedAt.timeIntervalSince($0), 0) } ?? 0
        let microphoneWriter = self.microphoneWriter
        let systemCapture = self.systemCapture
        let silent = await silentTracks()

        tearDown()

        var failures: [TrackKind: String] = [:]
        if let message = microphoneWriter?.failureMessage() { failures[.microphone] = message }
        if let message = systemCapture?.writeFailure() { failures[.system] = message }
        return CaptureStop(endedAt: endedAt, durationSeconds: duration, trackFailures: failures, silentTracks: silent)
    }

    public func levels() async -> [TrackKind: Double] {
        meters.snapshot()
    }

    public func silentTracks() async -> Set<TrackKind> {
        guard let startedAt, let source, source.includesMicrophone,
              Date().timeIntervalSince(startedAt) >= Self.silenceVerdictDelay,
              (meters.peak(for: .microphone) ?? 0) == 0 else { return [] }
        return [.microphone]
    }

    // MARK: Microphone

    /// Returns the moment capture started, which anchors the timeline of every track.
    private func startMicrophone(writingTo url: URL, source: CaptureSource) throws -> Date {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // In mic+system mode the system audio plays through the speakers and
        // gets picked up acoustically by the built-in microphone, causing an
        // echo when the two tracks are combined. Enable macOS voice processing
        // (acoustic echo cancellation + noise suppression) on the input node
        // so the mic track has the speaker signal subtracted out.
        if source == .microphoneAndSystemAudio {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                // Voice processing ducks all non-VP audio (browsers, music
                // players) system-wide by default, which mutes exactly the
                // audio this mode is trying to record. Keep ducking at the
                // minimum so Chrome/Spotify stay audible; AEC still removes
                // the speaker signal from the mic track.
                inputNode.voiceProcessingOtherAudioDuckingConfiguration =
                    AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                        enableAdvancedDucking: false,
                        duckingLevel: .min
                    )
            } catch {
                // Voice processing may not be available on every audio device
                // (e.g. some virtual aggregate inputs). Fall back to raw mic.
            }
        }

        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw CaptureError.startFailed("No microphone is available.")
        }
        let fileFormat = Self.fileFormat(for: inputFormat)
        let writer = try TimelineAudioWriter(outputURL: url, format: fileFormat)
        Self.installTap(on: engine, writer: writer, fileFormat: fileFormat, meters: meters)

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw CaptureError.startFailed("AVAudioEngine failed to start. \(error.localizedDescription)")
        }
        let startedAt = Date()
        writer.setTimelineStart(startedAt)

        microphoneEngine = engine
        microphoneWriter = writer
        microphoneFileFormat = fileFormat
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.microphoneConfigurationChanged() }
        }
        return startedAt
    }

    /// With voice processing enabled the built-in mic reports a >2-channel
    /// format (identical channels). Persist channel 0 as mono: the file
    /// stays 5× smaller, and downstream conversion can't handle >2ch
    /// input — AVAudioConverter silently zeroes it.
    private static func fileFormat(for inputFormat: AVAudioFormat) -> AVAudioFormat {
        guard inputFormat.channelCount > 2, let mono = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else { return inputFormat }
        return mono
    }

    private static func installTap(
        on engine: AVAudioEngine,
        writer: TimelineAudioWriter,
        fileFormat: AVAudioFormat,
        meters: MeterBox
    ) {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let reduceToMono = inputFormat.channelCount > 2
        let targetFrames = Int((inputFormat.sampleRate * 0.45).rounded())
        let bufferSize = AVAudioFrameCount(max(4096, min(32_768, targetFrames)))

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { rawBuffer, _ in
            guard var buffer = reduceToMono ? rawBuffer.lorre_monoChannelZero() : rawBuffer else { return }
            // Only after a device change can the input differ from what the file was created with.
            if buffer.format != fileFormat {
                guard let converted = try? RecorderAudioUtilities.convert(buffer, to: fileFormat) else { return }
                buffer = converted
            }
            writer.write(buffer)
            meters.set(buffer.lorre_meterLevel(), for: .microphone)
            meters.notePeak(buffer.lorre_peak(), for: .microphone)
        }
    }

    /// The input device changed (headset plugged in or removed). The engine has stopped; restart it
    /// into the same file. The writer pads the gap, so the track stays on the timeline.
    private func microphoneConfigurationChanged() {
        guard let engine = microphoneEngine, let writer = microphoneWriter, let fileFormat = microphoneFileFormat else {
            return
        }
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            logger.error("Microphone input disappeared; the microphone track ends here")
            return
        }
        Self.installTap(on: engine, writer: writer, fileFormat: fileFormat, meters: meters)
        do {
            if !engine.isRunning { try engine.start() }
            logger.info("Microphone input changed; capture continues")
        } catch {
            logger.error("Could not restart the microphone after a device change: \(error.localizedDescription)")
        }
    }

    // MARK: Shared

    private func tearDown() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        if let engine = microphoneEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        microphoneWriter?.finish()
        systemCapture?.stop()

        microphoneEngine = nil
        microphoneWriter = nil
        microphoneFileFormat = nil
        systemCapture = nil
        source = nil
        startedAt = nil
        meters.reset()
        sleepGuard.end()
    }

    /// System audio capture is also governed by the microphone permission (plus the audio-capture
    /// entitlement applied at signing), so every source needs it.
    private static func ensureMicrophonePermission() async throws {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        default:
            granted = false
        }
        guard granted else {
            throw CaptureError.permissionDenied(
                "Lorre has no access to the microphone. Allow it in System Settings → Privacy & Security → Microphone."
            )
        }
    }
}
#endif
