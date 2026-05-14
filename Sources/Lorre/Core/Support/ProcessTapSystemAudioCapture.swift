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

    private let ioQueue = DispatchQueue(
        label: "Lorre.ProcessTap.IO",
        qos: .userInteractive
    )

    // MARK: - Start

    func start(
        outputURL: URL,
        onPCMBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onMeterLevel: @escaping @Sendable (Double) -> Void
    ) async throws -> StartResult {
        return try startSynchronously(
            outputURL: outputURL,
            onPCMBuffer: onPCMBuffer,
            onMeterLevel: onMeterLevel
        )
    }

    // MARK: - Stop

    /// Stop the IOProc, destroy the aggregate device and process tap. Safe to
    /// call multiple times; subsequent calls are no-ops.
    func stop() {
        let (aggregateID, tapID, procID, writer) = lock.withLock {
            let a = self.aggregateID
            let t = self.tapID
            let p = self.ioProcID
            let w = self.writer
            self.aggregateID = nil
            self.tapID = nil
            self.ioProcID = nil
            self.writer = nil
            return (a, t, p, w)
        }

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
        onPCMBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onMeterLevel: @escaping @Sendable (Double) -> Void
    ) throws -> StartResult {
        var createdTapID: AudioObjectID? = nil
        var createdAggregateID: AudioObjectID? = nil
        var createdProcID: AudioDeviceIOProcID? = nil

        // Writer file is always created first so the CAF exists on disk
        // regardless of whether the tap activates. Downstream combine logic
        // expects the file at `outputURL` — an empty header file is treated
        // as a silent system stem.
        let writerFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let writer = try ProcessTapAudioWriter(outputURL: outputURL, format: writerFormat)

        do {
            // ── Step 1: Enumerate process AudioObjectIDs, exclude self ───────
            // On macOS 15.7.3 the `stereoGlobalTapButExcludeProcesses`
            // initializer reliably produces all-zero buffers — verified
            // against insidegui/AudioCap which only works on this machine when
            // tapping a specific PID via the include-list initializer. So we
            // pass the inverse: every process except ourselves as the include
            // list. Functionally equivalent, but goes through the working
            // CoreAudio code path.
            let (_, otherProcessIDs) = try enumerateProcessAudioObjectIDs()

            // No process is currently outputting audio. Recording proceeds
            // without a tap — the writer file stays at header-only size and
            // the system stem is treated as silence. Mic capture (if any) is
            // unaffected.
            if otherProcessIDs.isEmpty {
                logger.warning("No process is currently producing audio; system audio stem will be silent for this recording.")
                lock.withLock {
                    self.writer = writer
                }
                return StartResult(outputURL: outputURL, startedAt: Date())
            }

            // ── Step 2: Create CATapDescription ──────────────────────────────
            // Setting the UUID explicitly lets us reference the same value in
            // the aggregate device's tap list without round-tripping through
            // `kAudioTapPropertyUID` (matches AudioCap's reference pattern).
            let description = CATapDescription(
                stereoMixdownOfProcesses: otherProcessIDs
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

            // ── Step 7: Install the I/O proc ──────────────────────────────────
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

            // ── Step 8: Start the device ──────────────────────────────────────
            let startStatus = AudioDeviceStart(aggregateID, procID)
            guard startStatus == noErr else {
                throw LorreError.recordingStartFailed(
                    "AudioDeviceStart failed (status: \(startStatus))."
                )
            }

            let startedAt = Date()
            logger.info("ProcessTapSystemAudioCapture started — writing to \(outputURL.lastPathComponent)")

            // ── Step 9: Commit to stored state ────────────────────────────────
            lock.withLock {
                self.tapID = tapID
                self.aggregateID = aggregateID
                self.ioProcID = procID
                self.writer = writer
            }

            return StartResult(outputURL: outputURL, startedAt: startedAt)

        } catch {
            // Partial-failure teardown matches the live stop() sequence:
            //   IOProc → aggregate → tap.
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

    /// Enumerates process AudioObjectIDs known to CoreAudio. Returns
    /// `(ownID, currentlyOutputtingOthers)` — the others list contains only
    /// processes whose `kAudioProcessPropertyIsRunningOutput` is true. On
    /// macOS 15.7.3 the tap appears to silently break when given idle PIDs
    /// in the include list, so we only pass the active producers.
    private func enumerateProcessAudioObjectIDs() throws -> (own: AudioObjectID, others: [AudioObjectID]) {
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
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioProcessPropertyIsRunningOutput),
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
                continue
            }

            var isOutputting: UInt32 = 0
            var outputSize = UInt32(MemoryLayout<UInt32>.size)
            let outputStatus = AudioObjectGetPropertyData(
                objectID, &outputAddress, 0, nil, &outputSize, &isOutputting
            )
            if outputStatus == noErr, isOutputting != 0 {
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

        guard !others.isEmpty else {
            throw LorreError.recordingStartFailed(
                "No other process is currently producing audio output. "
                + "Start playing audio from the app you want to capture, then start the recording."
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
