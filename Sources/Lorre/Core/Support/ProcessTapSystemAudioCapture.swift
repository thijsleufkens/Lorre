#if canImport(AVFoundation)
import AVFoundation
import CoreAudio
import Foundation
import os

/// Captures system audio (all running processes except this process) using
/// macOS 15's CoreAudio Process Tap API. Wraps the tap in a private aggregate
/// device so AVAudioEngine can pull buffers like any other input device.
///
/// Replaces the previous ScreenCaptureKit-based capture path. Permission is
/// granted via the existing macOS Microphone TCC service —
/// `NSMicrophoneUsageDescription` is sufficient; no new Info.plist key is needed.
///
/// Output format: Float32, 48 kHz, 2-channel, non-interleaved — identical to
/// the previous SCStream-based system audio writer so downstream mixing and
/// transcription remain unchanged.
///
/// Usage:
/// ```swift
/// let capture = ProcessTapSystemAudioCapture()
/// let result = try await capture.start(
///     outputURL: url,
///     onPCMBuffer: { buffer in ... },
///     onMeterLevel: { level in ... }
/// )
/// // ... later:
/// capture.stop()
/// ```
@available(macOS 15.0, *)
final class ProcessTapSystemAudioCapture: @unchecked Sendable {
    struct StartResult {
        /// The output `.caf` file the capture writes to.
        let outputURL: URL
        /// The time the engine started delivering audio buffers.
        let startedAt: Date
    }

    private let logger = Logger(subsystem: "lorre", category: "ProcessTapSystemAudio")

    /// Thread-safety: all mutable state is guarded by `lock`.
    /// `NSLock.withLock` is used so callers need not call lock/unlock manually.
    private let lock = NSLock()
    private var tapID: AudioObjectID?
    private var aggregateID: AudioObjectID?
    private var engine: AVAudioEngine?
    private var writer: ProcessTapAudioWriter?

    // MARK: - Start

    /// Build the process tap + aggregate device, wire AVAudioEngine, install a
    /// tap callback that writes to `outputURL` and calls `onPCMBuffer` /
    /// `onMeterLevel` on every delivered buffer.
    ///
    /// - Parameters:
    ///   - outputURL: Destination `.caf` file. Must not already exist.
    ///   - onPCMBuffer: Called on every audio buffer — use for preview / meter.
    ///   - onMeterLevel: Called with the computed meter level on every buffer.
    /// - Returns: A `StartResult` describing the output file and start time.
    /// - Throws: `LorreError.recordingStartFailed` with a descriptive message
    ///   including any failing `OSStatus` codes.
    func start(
        outputURL: URL,
        onPCMBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onMeterLevel: @escaping @Sendable (Double) -> Void
    ) async throws -> StartResult {
        // Delegate to a synchronous implementation so we avoid using NSLock
        // in an async context (NSLock.lock() is unavailable in async contexts
        // under Swift 6 strict concurrency).
        return try startSynchronously(
            outputURL: outputURL,
            onPCMBuffer: onPCMBuffer,
            onMeterLevel: onMeterLevel
        )
    }

    // MARK: - Stop

    /// Stop the engine, remove the tap, destroy the aggregate device and process
    /// tap. Safe to call multiple times; subsequent calls are no-ops.
    func stop() {
        let (engine, aggregateID, tapID, writer) = lock.withLock {
            let e = self.engine
            let a = self.aggregateID
            let t = self.tapID
            let w = self.writer
            self.engine = nil
            self.aggregateID = nil
            self.tapID = nil
            self.writer = nil
            return (e, a, t, w)
        }

        // Stop the engine and remove the audio tap before releasing CoreAudio
        // objects so callbacks cannot fire after teardown begins.
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        // Discovery gotcha #7: destroy aggregate device BEFORE the tap.
        if let aggregate = aggregateID {
            let status = AudioHardwareDestroyAggregateDevice(aggregate)
            if status != noErr {
                logger.error("AudioHardwareDestroyAggregateDevice failed (status: \(status))")
            }
        }
        if let tap = tapID {
            let status = AudioHardwareDestroyProcessTap(tap)
            if status != noErr {
                logger.error("AudioHardwareDestroyProcessTap failed (status: \(status))")
            }
        }

        writer?.finish()
        logger.info("ProcessTapSystemAudioCapture stopped")
    }

    /// Returns the latest write-failure message from the underlying writer, or nil if none.
    /// Matches the contract of `SystemAudioCaptureBox.failure()` so the recording service
    /// can poll the same way regardless of capture backend.
    func writeFailure() -> String? {
        lock.withLock { writer?.failureMessage() }
    }

    // MARK: - Deinit

    deinit {
        stop()
    }

    // MARK: - Private synchronous implementation

    /// Synchronous implementation of `start` — kept separate so `NSLock.withLock`
    /// and all state mutations stay in a non-async context.
    private func startSynchronously(
        outputURL: URL,
        onPCMBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onMeterLevel: @escaping @Sendable (Double) -> Void
    ) throws -> StartResult {
        // Capture resources that need teardown on partial failure.
        var createdTapID: AudioObjectID? = nil
        var createdAggregateID: AudioObjectID? = nil

        do {
            // ── Step 1: Resolve this process's PID → AudioObjectID ───────────
            let ownAudioObjectID = try resolveOwnAudioObjectID()
            logger.debug("Own process AudioObjectID: \(ownAudioObjectID)")

            // ── Step 2: Create CATapDescription ──────────────────────────────
            // Tap all system audio, excluding this process.
            // `stereoGlobalTapButExcludeProcesses` requires macOS 14.0+.
            let description = CATapDescription(
                stereoGlobalTapButExcludeProcesses: [ownAudioObjectID]
            )
            // `isPrivate = false` → the tap is not hidden from other processes.
            // `privateTap` was renamed to `isPrivate` in Swift (gotcha #1).
            description.isPrivate = false
            description.muteBehavior = .unmuted

            // ── Step 3: Create the process tap ───────────────────────────────
            var tapID = AudioObjectID(kAudioObjectUnknown)
            let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
            guard tapStatus == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
                throw LorreError.recordingStartFailed(
                    "AudioHardwareCreateProcessTap failed (status: \(tapStatus))."
                )
            }
            createdTapID = tapID
            logger.debug("Process tap created: \(tapID)")

            // ── Step 4: Query tap UID string ──────────────────────────────────
            // The aggregate device needs the tap's UID string, not its numeric ID.
            let tapUID = try queryTapUID(tapObjectID: tapID)
            logger.debug("Tap UID: \(tapUID)")

            // ── Step 5: Build + create aggregate device ───────────────────────
            let aggregateUID = "lorre.process-tap.aggregate.\(UUID().uuidString)"
            let tapList: [[String: Any]] = [
                [kAudioSubTapUIDKey: tapUID]
            ]
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceUIDKey: aggregateUID,
                kAudioAggregateDeviceNameKey: "Lorre System Audio",
                kAudioAggregateDeviceTapListKey: tapList,
                kAudioAggregateDeviceIsPrivateKey: 1,
                kAudioAggregateDeviceIsStackedKey: 0
            ]

            var aggregateID = AudioObjectID(kAudioObjectUnknown)
            let aggregateStatus = AudioHardwareCreateAggregateDevice(
                aggregateDescription as CFDictionary,
                &aggregateID
            )
            guard aggregateStatus == noErr, aggregateID != AudioObjectID(kAudioObjectUnknown) else {
                throw LorreError.recordingStartFailed(
                    "AudioHardwareCreateAggregateDevice failed (status: \(aggregateStatus))."
                )
            }
            createdAggregateID = aggregateID
            logger.debug("Aggregate device created: \(aggregateID)")

            // ── Step 6: Build AVAudioEngine and point it at the aggregate ─────
            let engine = AVAudioEngine()
            guard let inputUnit = engine.inputNode.audioUnit else {
                throw LorreError.recordingStartFailed(
                    "AVAudioEngine inputNode has no underlying AudioUnit."
                )
            }

            var deviceID: AudioDeviceID = aggregateID
            let setDeviceStatus = AudioUnitSetProperty(
                inputUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard setDeviceStatus == noErr else {
                throw LorreError.recordingStartFailed(
                    "Could not set aggregate device on AVAudioEngine input "
                    + "(status: \(setDeviceStatus))."
                )
            }

            // ── Step 7: Create the output file writer ─────────────────────────
            // Format matches the previous SCStream-based writer exactly:
            // Float32, 48 kHz, 2-channel, non-interleaved.
            let fileFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )!
            let writer = try ProcessTapAudioWriter(outputURL: outputURL, format: fileFormat)

            // ── Step 8: Install tap on input node ─────────────────────────────
            let inputFormat = engine.inputNode.inputFormat(forBus: 0)
            logger.debug("Input format: \(inputFormat)")

            // Buffer size: target ~100 ms at 48 kHz ≈ 4800 frames.
            // Clamped to [4096, 32768] matching the microphone path.
            let targetFrames = Int((inputFormat.sampleRate * 0.1).rounded())
            let bufferSize = AVAudioFrameCount(max(4096, min(32_768, targetFrames)))

            engine.inputNode.removeTap(onBus: 0)
            engine.inputNode.installTap(
                onBus: 0,
                bufferSize: bufferSize,
                format: inputFormat
            ) { [weak writer] buffer, _ in
                // Convert to the canonical format if the engine delivers a
                // different layout (e.g. hardware not running at 48 kHz).
                let canonical: AVAudioPCMBuffer
                if buffer.format.sampleRate == 48_000
                    && buffer.format.channelCount == 2
                    && buffer.format.commonFormat == .pcmFormatFloat32
                {
                    canonical = buffer
                } else if let converted = try? RecorderAudioUtilities.convert(buffer, to: fileFormat) {
                    canonical = converted
                } else {
                    return
                }

                writer?.write(canonical)
                onMeterLevel(canonical.lorre_meterLevel())
                onPCMBuffer(canonical)
            }

            // ── Step 9: Start the engine ──────────────────────────────────────
            do {
                try engine.start()
            } catch {
                engine.inputNode.removeTap(onBus: 0)
                throw LorreError.recordingStartFailed(
                    "AVAudioEngine failed to start. \(error.localizedDescription)"
                )
            }

            let startedAt = Date()
            logger.info("ProcessTapSystemAudioCapture started — writing to \(outputURL.lastPathComponent)")

            // ── Step 10: Commit to stored state ───────────────────────────────
            lock.withLock {
                self.tapID = tapID
                self.aggregateID = aggregateID
                self.engine = engine
                self.writer = writer
            }

            return StartResult(outputURL: outputURL, startedAt: startedAt)

        } catch {
            // Partial-failure teardown: aggregate must be destroyed before tap.
            if let aggregate = createdAggregateID {
                AudioHardwareDestroyAggregateDevice(aggregate)
            }
            if let tap = createdTapID {
                AudioHardwareDestroyProcessTap(tap)
            }
            throw error
        }
    }

    // MARK: - Private helpers

    /// Translates the current process's PID to its `AudioObjectID` by querying
    /// `kAudioHardwarePropertyProcessObjectList` and matching PIDs.
    ///
    /// - Returns: The `AudioObjectID` for this process.
    /// - Throws: `LorreError.recordingStartFailed` if the lookup fails.
    private func resolveOwnAudioObjectID() throws -> AudioObjectID {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // 1. Fetch the list of process AudioObjectIDs from the system object.
        var listAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyProcessObjectList),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &listAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else {
            throw LorreError.recordingStartFailed(
                "Could not query process object list size (status: \(status))."
            )
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: count
        )
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &listAddress,
            0, nil,
            &dataSize,
            &objectIDs
        )
        guard status == noErr else {
            throw LorreError.recordingStartFailed(
                "Could not fetch process object list (status: \(status))."
            )
        }

        // 2. Match each object's PID against our own PID.
        var pidAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioProcessPropertyPID),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

        for objectID in objectIDs {
            var processPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            let pidStatus = AudioObjectGetPropertyData(
                objectID,
                &pidAddress,
                0, nil,
                &pidSize,
                &processPID
            )
            if pidStatus == noErr, processPID == ownPID {
                return objectID
            }
        }

        // Realistically a running app always has a CoreAudio entry, so reaching
        // here indicates a system-level error.
        let pid = ownPID
        logger.warning("Own process PID \(pid) not found in CoreAudio process list.")
        throw LorreError.recordingStartFailed(
            "Could not find this process (PID \(ownPID)) in the CoreAudio "
            + "process object list. Process tap cannot be created safely."
        )
    }

    /// Queries `kAudioTapPropertyUID` on the tap object to obtain the UID
    /// string needed for the aggregate device's tap list.
    ///
    /// Uses `withUnsafeMutableBytes` + `Unmanaged<CFString>` to avoid the
    /// Swift 6 warning about forming `UnsafeMutableRawPointer` to an object
    /// reference (discovery gotcha #3).
    ///
    /// - Parameter tapObjectID: The tap's `AudioObjectID`.
    /// - Returns: The tap's UID as a `String`.
    /// - Throws: `LorreError.recordingStartFailed` on any failure.
    private func queryTapUID(tapObjectID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioTapPropertyUID),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

        // Use Unmanaged<CFString> to avoid the Swift 6 UnsafeMutableRawPointer
        // warning that occurs when passing a `CFString?` directly.
        var unmanagedUID: Unmanaged<CFString>? = nil
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = withUnsafeMutableBytes(of: &unmanagedUID) { rawPtr in
            AudioObjectGetPropertyData(
                tapObjectID,
                &address,
                0, nil,
                &dataSize,
                rawPtr.baseAddress!
            )
        }

        guard status == noErr, let unmanaged = unmanagedUID else {
            throw LorreError.recordingStartFailed(
                "Could not query process tap UID (status: \(status))."
            )
        }

        // `kAudioTapPropertyUID` returns a +1 retained CFString (Create Rule).
        let uid = unmanaged.takeRetainedValue() as String
        guard !uid.isEmpty else {
            throw LorreError.recordingStartFailed(
                "Process tap UID is unexpectedly empty."
            )
        }
        return uid
    }
}

// MARK: - ProcessTapAudioWriter

/// Writes incoming PCM buffers to a `.caf` file. Output format matches the
/// previous SCStream-based system audio writer exactly:
/// Float32, 48 kHz, 2-channel, non-interleaved (discovery notes §Buffer format).
///
/// Thread safety: `write(_:)` and `finish()` may be called from different
/// queues (audio tap queue vs stop path). An `NSLock` guards the file write.
@available(macOS 15.0, *)
final class ProcessTapAudioWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let lock = NSLock()
    private var writeFailureMessage: String?

    /// Create a writer that will write Float32 / 48 kHz / 2ch / non-interleaved
    /// PCM data to `outputURL` in Core Audio Format.
    ///
    /// - Parameters:
    ///   - outputURL: The destination file path (`.caf` extension expected).
    ///   - format: The `AVAudioFormat` used for writing. Must be PCM Float32.
    init(outputURL: URL, format: AVAudioFormat) throws {
        // `AVAudioFile(forWriting:settings:)` creates the file and writes the
        // CAF header. Using `format.settings` preserves whatever AVAudioFormat
        // encodes, matching the previous SCStream writer exactly.
        self.file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
    }

    /// Write a buffer to the file. Silently drops subsequent buffers after the
    /// first write failure (consistent with `CaptureFileWriterBox` in the
    /// existing service).
    func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard writeFailureMessage == nil else { return }
            do {
                try file.write(from: buffer)
            } catch {
                writeFailureMessage = error.localizedDescription
            }
        }
    }

    /// Returns the first write failure message, if any.
    func failureMessage() -> String? {
        lock.withLock { writeFailureMessage }
    }

    /// Explicit finish hook for symmetry with `stop()`. `AVAudioFile` finalizes
    /// the CAF header on `deinit`; this method is a no-op provided for clarity.
    func finish() {
        // No-op: AVAudioFile finalizes on deinit.
    }
}
#endif
