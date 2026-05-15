#if canImport(AVFoundation)
import AVFoundation
import CoreAudio
import Foundation
import os

/// Captures system audio (all running processes except this process) using
/// macOS 15's CoreAudio Process Tap API. Wraps the tap in a private aggregate
/// device anchored to the default system output device, and pulls PCM buffers
/// through `AudioDeviceCreateIOProcIDWithBlock`.
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
        let outputURL: URL
        let startedAt: Date
    }

    private let logger = Logger(subsystem: "lorre", category: "ProcessTapSystemAudio")

    private let lock = NSLock()
    private var tapID: AudioObjectID?
    private var aggregateID: AudioObjectID?
    private var ioProcID: AudioDeviceIOProcID?
    private var writer: ProcessTapAudioWriter?
    private var warmer: AudioOutputWarmer?

    private let ioQueue = DispatchQueue(
        label: "Lorre.ProcessTap.IO",
        qos: .userInteractive
    )

    // MARK: - Start

    /// - Parameters:
    ///   - outputWarmerRequired: When `true`, this capture spins up a silent
    ///     `AVAudioEngine` so that Lorre registers as a "producing output"
    ///     process — required for the tap to deliver audio in system-only
    ///     mode. Pass `false` when the caller is already running a mic
    ///     `AVAudioEngine` in parallel; that engine keeps the audio
    ///     subsystem warm and a second engine can cause monitoring feedback
    ///     (acoustic echo through speakers).
    func start(
        outputURL: URL,
        outputWarmerRequired: Bool,
        onPCMBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onMeterLevel: @escaping @Sendable (Double) -> Void
    ) async throws -> StartResult {
        return try startSynchronously(
            outputURL: outputURL,
            outputWarmerRequired: outputWarmerRequired,
            onPCMBuffer: onPCMBuffer,
            onMeterLevel: onMeterLevel
        )
    }

    // MARK: - Stop

    /// Stop the IOProc, destroy the aggregate device and process tap. Safe to
    /// call multiple times; subsequent calls are no-ops.
    func stop() {
        let (aggregateID, tapID, procID, writer, warmer) = lock.withLock {
            let a = self.aggregateID
            let t = self.tapID
            let p = self.ioProcID
            let w = self.writer
            let wm = self.warmer
            self.aggregateID = nil
            self.tapID = nil
            self.ioProcID = nil
            self.writer = nil
            self.warmer = nil
            return (a, t, p, w, wm)
        }

        warmer?.stop()

        if let aggregate = aggregateID, let procID {
            let stopStatus = AudioDeviceStop(aggregate, procID)
            if stopStatus != noErr {
                logger.error("AudioDeviceStop failed (status: \(stopStatus))")
            }
            let destroyProcStatus = AudioDeviceDestroyIOProcID(aggregate, procID)
            if destroyProcStatus != noErr {
                logger.error("AudioDeviceDestroyIOProcID failed (status: \(destroyProcStatus))")
            }
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

    private func startSynchronously(
        outputURL: URL,
        outputWarmerRequired: Bool,
        onPCMBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onMeterLevel: @escaping @Sendable (Double) -> Void
    ) throws -> StartResult {
        var createdTapID: AudioObjectID? = nil
        var createdAggregateID: AudioObjectID? = nil
        var createdProcID: AudioDeviceIOProcID? = nil

        // ── Step 0: Optionally start a silent AVAudioEngine output ──────────
        // Empirically the tap only delivers buffers when at least one process
        // is producing audio at tap-creation time. In system-only mode we
        // register Lorre as a producer by playing silence ourselves. In
        // mic+system mode the caller is already running a mic AVAudioEngine
        // which keeps the audio subsystem warm; spinning up a second engine
        // creates a monitoring feedback path (speaker → mic acoustic echo).
        var warmerOwnership: AudioOutputWarmer? = nil
        if outputWarmerRequired {
            let warmer = try AudioOutputWarmer()
            try warmer.start()
            // Give CoreAudio ~150ms to register us as a producing process
            // before we enumerate the process list and create the tap.
            Thread.sleep(forTimeInterval: 0.15)
            warmerOwnership = warmer
        }

        do {
            // ── Step 1: Enumerate process AudioObjectIDs ─────────────────────
            // We don't filter on `kAudioProcessPropertyIsRunningOutput` — with
            // the warmer running our own process is producing, which keeps
            // the audio subsystem warm. We deliberately EXCLUDE ourselves
            // from the tap list so Lorre's silent buffers don't get mixed
            // into the recording (which fragments the captured audio and
            // breaks downstream speech detection).
            let (_, otherProcessIDs) = try enumerateAllProcessAudioObjectIDs()
            let processList = otherProcessIDs

            // ── Step 2: Create CATapDescription ──────────────────────────────
            // Setting the UUID explicitly lets us reference the same value in
            // the aggregate device's tap list without round-tripping through
            // `kAudioTapPropertyUID` (matches AudioCap's reference pattern).
            let description = CATapDescription(
                stereoMixdownOfProcesses: processList
            )
            description.uuid = UUID()
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
            let tapUID = description.uuid.uuidString

            // ── Step 4: Query the tap's native stream format ──────────────────
            let tapFormat = try queryTapStreamFormat(tapObjectID: tapID)

            // ── Step 5: Resolve default system output device UID for clock ────
            // A tap-only aggregate has no hardware clock and never gets its
            // I/O cycle pumped on system-audio-only mode. Anchoring the
            // aggregate to the default output device gives it a real clock.
            let outputUID = try queryDefaultSystemOutputDeviceUID()

            // ── Step 6: Build + create aggregate device ───────────────────────
            let aggregateUID = "lorre.process-tap.aggregate.\(UUID().uuidString)"
            let tapList: [[String: Any]] = [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
            let subDeviceList: [[String: Any]] = [
                [kAudioSubDeviceUIDKey: outputUID]
            ]
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceUIDKey: aggregateUID,
                kAudioAggregateDeviceNameKey: "Lorre System Audio",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceSubDeviceListKey: subDeviceList,
                kAudioAggregateDeviceTapListKey: tapList
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

            // ── Step 7: Create the output file writer ─────────────────────────
            // Writer format matches the previous SCStream-based writer exactly:
            // Float32, 48 kHz, 2-channel, non-interleaved.
            let writerFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )!
            let writer = try ProcessTapAudioWriter(outputURL: outputURL, format: writerFormat)

            // ── Step 8: Install the I/O proc ──────────────────────────────────
            var procID: AudioDeviceIOProcID? = nil
            let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
                &procID,
                aggregateID,
                ioQueue
            ) { [weak writer] _, inputData, _, _, _ in
                guard let writer else { return }

                guard let rawBuffer = AVAudioPCMBuffer(
                    pcmFormat: tapFormat,
                    bufferListNoCopy: inputData,
                    deallocator: nil
                ) else {
                    return
                }

                let canonical: AVAudioPCMBuffer
                if rawBuffer.format.sampleRate == writerFormat.sampleRate
                    && rawBuffer.format.channelCount == writerFormat.channelCount
                    && rawBuffer.format.commonFormat == writerFormat.commonFormat
                    && rawBuffer.format.isInterleaved == writerFormat.isInterleaved
                {
                    canonical = rawBuffer
                } else if let converted = try? RecorderAudioUtilities.convert(
                    rawBuffer,
                    to: writerFormat
                ) {
                    canonical = converted
                } else {
                    return
                }

                guard canonical.frameLength > 0 else { return }

                writer.write(canonical)
                onMeterLevel(canonical.lorre_meterLevel())
                onPCMBuffer(canonical)
            }

            guard ioStatus == noErr, let procID else {
                throw LorreError.recordingStartFailed(
                    "AudioDeviceCreateIOProcIDWithBlock failed (status: \(ioStatus))."
                )
            }
            createdProcID = procID

            // ── Step 9: Start the device ──────────────────────────────────────
            let startStatus = AudioDeviceStart(aggregateID, procID)
            guard startStatus == noErr else {
                throw LorreError.recordingStartFailed(
                    "AudioDeviceStart failed (status: \(startStatus))."
                )
            }

            let startedAt = Date()
            logger.info("ProcessTapSystemAudioCapture started — writing to \(outputURL.lastPathComponent)")

            // ── Step 10: Commit to stored state ───────────────────────────────
            lock.withLock {
                self.tapID = tapID
                self.aggregateID = aggregateID
                self.ioProcID = procID
                self.writer = writer
                self.warmer = warmerOwnership
            }
            warmerOwnership = nil

            return StartResult(outputURL: outputURL, startedAt: startedAt)

        } catch {
            // Partial-failure teardown matches the live stop() sequence:
            //   warmer → IOProc → aggregate → tap.
            warmerOwnership?.stop()
            if let aggregate = createdAggregateID, let procID = createdProcID {
                AudioDeviceStop(aggregate, procID)
                AudioDeviceDestroyIOProcID(aggregate, procID)
            }
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

    /// Enumerates every process AudioObjectID known to CoreAudio and splits
    /// out this process's own ID. No filter on `IsRunningOutput` — callers
    /// rely on the `AudioOutputWarmer` to ensure the tap has at least one
    /// producing process at creation time (ourselves), and we want all other
    /// PIDs in the include list so the tap can mix in any of them as they
    /// start producing audio later.
    private func enumerateAllProcessAudioObjectIDs() throws -> (own: AudioObjectID, others: [AudioObjectID]) {
        let ownPID = ProcessInfo.processInfo.processIdentifier

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

        var pidAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioProcessPropertyPID),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

        var ownAudioObjectID = AudioObjectID(kAudioObjectUnknown)
        var others: [AudioObjectID] = []
        others.reserveCapacity(objectIDs.count)

        for objectID in objectIDs {
            var processPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            let pidStatus = AudioObjectGetPropertyData(
                objectID, &pidAddress, 0, nil, &pidSize, &processPID
            )
            guard pidStatus == noErr else { continue }

            if processPID == ownPID {
                ownAudioObjectID = objectID
            } else {
                others.append(objectID)
            }
        }

        guard ownAudioObjectID != AudioObjectID(kAudioObjectUnknown) else {
            let pid = ownPID
            logger.warning("Own process PID \(pid, privacy: .public) not found in CoreAudio process list.")
            throw LorreError.recordingStartFailed(
                "Could not find this process (PID \(ownPID)) in the CoreAudio "
                + "process object list. Process tap cannot be created safely."
            )
        }

        return (ownAudioObjectID, others)
    }

    /// Queries `kAudioTapPropertyUID` on the tap object to obtain the UID
    /// string needed for the aggregate device's tap list.
    private func queryTapUID(tapObjectID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioTapPropertyUID),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

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

        let uid = unmanaged.takeRetainedValue() as String
        guard !uid.isEmpty else {
            throw LorreError.recordingStartFailed(
                "Process tap UID is unexpectedly empty."
            )
        }
        return uid
    }

    /// Queries `kAudioTapPropertyFormat` on the tap to obtain the native
    /// `AudioStreamBasicDescription` and wraps it in an `AVAudioFormat` so the
    /// I/O proc can construct `AVAudioPCMBuffer` instances over the raw
    /// `AudioBufferList` it receives.
    private func queryTapStreamFormat(tapObjectID: AudioObjectID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioTapPropertyFormat),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            tapObjectID,
            &address,
            0, nil,
            &size,
            &asbd
        )
        guard status == noErr else {
            throw LorreError.recordingStartFailed(
                "Could not query tap stream format (status: \(status))."
            )
        }
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            throw LorreError.recordingStartFailed(
                "Tap stream format is not a valid PCM AVAudioFormat."
            )
        }
        return format
    }

    /// Resolves the UID of the current default system output device. Used as
    /// the aggregate's `MainSubDevice` so the aggregate inherits a real
    /// hardware clock — without this, the I/O proc never fires in
    /// system-audio-only recordings.
    private func queryDefaultSystemOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultSystemOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
            throw LorreError.recordingStartFailed(
                "Could not resolve default system output device (status: \(status))."
            )
        }
        return try queryDeviceUID(deviceID: deviceID)
    }

    /// Queries `kAudioDevicePropertyDeviceUID` for the given device.
    private func queryDeviceUID(deviceID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceUID),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var unmanagedUID: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = withUnsafeMutableBytes(of: &unmanagedUID) { rawPtr in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0, nil,
                &size,
                rawPtr.baseAddress!
            )
        }
        guard status == noErr, let unmanaged = unmanagedUID else {
            throw LorreError.recordingStartFailed(
                "Could not query device UID for AudioObjectID \(deviceID) (status: \(status))."
            )
        }
        let uid = unmanaged.takeRetainedValue() as String
        guard !uid.isEmpty else {
            throw LorreError.recordingStartFailed(
                "Device UID for AudioObjectID \(deviceID) is unexpectedly empty."
            )
        }
        return uid
    }
}

// MARK: - AudioOutputWarmer

/// Runs an `AVAudioEngine` that loops a zero-filled buffer at zero volume so
/// that Lorre registers as a "producing output" process in CoreAudio's
/// process list. This guarantees the include-list of the process tap has at
/// least one active producer at creation time (without that, the tap fires
/// the IOProc but every delivered buffer is all-zeros — verified on
/// macOS 15.7.3 ad-hoc-signed builds).
///
/// The warmer stays running for the entire recording so the tap keeps mixing
/// in any other listed process that starts producing audio later.
@available(macOS 15.0, *)
private final class AudioOutputWarmer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isRunning = false

    init() throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: 2
        ) else {
            throw LorreError.recordingStartFailed(
                "Could not allocate AVAudioFormat for output warmer."
            )
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
    }

    func start() throws {
        guard !isRunning else { return }
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800) else {
            throw LorreError.recordingStartFailed(
                "Could not allocate silent buffer for output warmer."
            )
        }
        buffer.frameLength = 4800

        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        try engine.start()
        player.play()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.stop() }
        isRunning = false
    }
}

// MARK: - ProcessTapAudioWriter

/// Writes incoming PCM buffers to a `.caf` file. Output format matches the
/// previous SCStream-based system audio writer exactly:
/// Float32, 48 kHz, 2-channel, non-interleaved (discovery notes §Buffer format).
///
/// Thread safety: `write(_:)` and `finish()` may be called from different
/// queues (IO proc queue vs stop path). An `NSLock` guards the file write.
@available(macOS 15.0, *)
final class ProcessTapAudioWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let lock = NSLock()
    private var writeFailureMessage: String?

    init(outputURL: URL, format: AVAudioFormat) throws {
        self.file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
    }

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

    func failureMessage() -> String? {
        lock.withLock { writeFailureMessage }
    }

    func finish() {
        // AVAudioFile finalizes the CAF header on deinit.
    }
}
#endif
