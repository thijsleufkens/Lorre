# System Audio Process Tap Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ScreenCaptureKit-based system audio capture with macOS 15 CoreAudio Process Tap, dropping the Screen Recording permission and the per-recording SCContentSharingPicker dialog.

**Architecture:** A new `ProcessTapSystemAudioCapture` actor encapsulates the Process Tap lifecycle (tap creation + aggregate-device wrapping + AVAudioEngine read + writer + live buffer stream). `AVFoundationRecorderService` swaps its `startSystemAudioCapture` path to call the new actor and deletes every ScreenCaptureKit reference. The microphone capture path, the mic+system mixing, and all writer / live preview / file format details remain identical so existing sessions and downstream code (transcript pipeline, live preview, stems) are untouched.

**Tech Stack:** Swift / SwiftUI / AppKit, CoreAudio (`CATapDescription`, `AudioHardwareCreateProcessTap`, `AudioHardwareCreateAggregateDevice`), AVFoundation (`AVAudioEngine`, `AVAudioFile`), macOS 15.

**Spec:** `docs/superpowers/specs/2026-05-14-process-tap-system-audio.md`

**Branch:** `claude/process-tap-system-audio` (already created; spec already committed)

---

## Toolchain note

Same as previous sub-projects:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift {build|test}
```

If `swift-tools-version: 6.3` blocks the locally installed Xcode 6.2.4 toolchain, temporarily lower `Package.swift` line 1 to `// swift-tools-version: 6.2` for build/test, revert before committing. Do not commit `Package.swift` toolchain changes.

After Task 2 the deployment target bumps from `.macOS(.v14)` to `.macOS(.v15)`. Xcode 16+ ships the macOS 15 SDK; if a step fails because the SDK is missing, the engineer needs Xcode 16 or newer installed at `/Applications/Xcode.app`.

---

## Task 1: Discovery — verify Process Tap API surface

Apple's documentation on `CATapDescription` and `AudioHardwareCreateProcessTap` is sparse. Before we touch the production code, write a tiny standalone Swift CLI that proves the API exists, observes the permission prompt, and captures a few seconds of system audio. The exact API names, argument order, and aggregate-device requirement get pinned down here.

**Files:**
- Create: `Sources/Lorre/Core/Support/ProcessTapDiscoveryNotes.md` — written findings, committed.
- (Local scratch: `/tmp/process-tap-probe.swift` — used during exploration, NOT committed.)

- [ ] **Step 1: Write a minimal probe**

Create `/tmp/process-tap-probe.swift`:

```swift
import Foundation
import CoreAudio
import AVFoundation

// Goal: create a Process Tap that captures all running processes EXCEPT this one,
// pipe its output through an aggregate device, read 2 seconds of audio buffers
// via AVAudioEngine, log buffer count + format, then tear everything down cleanly.

let myPID = getpid()
print("My PID: \(myPID)")

// 1. Construct the tap description.
let description = CATapDescription(stereoMixdownOfProcesses: [])
description.processes = []                    // Process selector. Empty = all processes
                                              // unless `exceptProcesses` is set.
description.muteBehavior = .unmuted
description.isPrivate = false
description.exceptProcesses = [myPID]         // exclude ourselves

// 2. Create the tap.
var tapID = AudioObjectID(kAudioObjectUnknown)
let status = AudioHardwareCreateProcessTap(description, &tapID)
guard status == noErr, tapID != kAudioObjectUnknown else {
    print("AudioHardwareCreateProcessTap failed: \(status)")
    exit(1)
}
print("Created tap: \(tapID)")

// 3. Wrap the tap in an aggregate device so AVAudioEngine can read it.
let aggregateUID = "lorre.probe.aggregate.\(UUID().uuidString)"
let tapList: [[String: Any]] = [
    [
        kAudioSubTapUIDKey: String(tapID)  // Note: actual key may differ; verify in CoreAudio headers
    ]
]
let aggregateDescription: [String: Any] = [
    kAudioAggregateDeviceUIDKey: aggregateUID,
    kAudioAggregateDeviceNameKey: "Lorre Probe Aggregate",
    kAudioAggregateDeviceTapListKey: tapList,  // Verify the exact key in CoreAudio headers
    kAudioAggregateDeviceIsPrivateKey: 1,
    kAudioAggregateDeviceIsStackedKey: 0
]
var aggregateID = AudioObjectID(kAudioObjectUnknown)
let aggStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
guard aggStatus == noErr else {
    print("AudioHardwareCreateAggregateDevice failed: \(aggStatus)")
    AudioHardwareDestroyProcessTap(tapID)
    exit(1)
}
print("Created aggregate: \(aggregateID)")

// 4. Use AVAudioEngine to read from the aggregate device.
// Set the engine's input to use the aggregate via kAudioOutputUnitProperty_CurrentDevice
// (or simpler: AVAudioSession.sharedInstance().setPreferredInput on macOS isn't supported;
// instead, swap the engine's input audio unit's CurrentDevice property).

let engine = AVAudioEngine()
let inputUnit = engine.inputNode.audioUnit!
var deviceID = aggregateID
let setStatus = AudioUnitSetProperty(
    inputUnit,
    kAudioOutputUnitProperty_CurrentDevice,
    kAudioUnitScope_Global,
    0,
    &deviceID,
    UInt32(MemoryLayout<AudioObjectID>.size)
)
guard setStatus == noErr else {
    print("AudioUnitSetProperty CurrentDevice failed: \(setStatus)")
    AudioHardwareDestroyAggregateDevice(aggregateID)
    AudioHardwareDestroyProcessTap(tapID)
    exit(1)
}

let inputFormat = engine.inputNode.inputFormat(forBus: 0)
print("Input format: \(inputFormat)")

var bufferCount = 0
engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
    bufferCount += 1
    if bufferCount % 10 == 0 {
        print("buffers=\(bufferCount) frames=\(buffer.frameLength)")
    }
}

try engine.start()
print("Engine started. Play something for 2 seconds…")
Thread.sleep(forTimeInterval: 2.0)

engine.stop()
engine.inputNode.removeTap(onBus: 0)
print("Total buffers: \(bufferCount)")

// 5. Teardown.
AudioHardwareDestroyAggregateDevice(aggregateID)
AudioHardwareDestroyProcessTap(tapID)
print("Done.")
```

Save it to `/tmp/process-tap-probe.swift`.

- [ ] **Step 2: Run the probe**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift /tmp/process-tap-probe.swift
```

Observe:
- Does macOS show an "Audio Recording" / "Lorre" permission prompt on first run? If yes, **grant it** and re-run.
- Does the probe complete without errors? What's the input format reported?
- Does `bufferCount` increase while audio plays on the system?
- What's the exact name of any API that the probe got wrong (compile errors guide you to the real names — Swift will suggest alternatives in the error message).

**Expected outcome:** the probe runs, prompts for permission once, captures buffers while you play music in another app. Sample rate typically 48 kHz, 2 channels stereo, Float32 PCM.

If anything fails: adjust the probe until it works. Keep notes of what you changed (which key name was wrong, which API signature was different, etc.). These notes become the discovery output.

- [ ] **Step 3: Document findings**

Create `Sources/Lorre/Core/Support/ProcessTapDiscoveryNotes.md` with the working API names and any surprises. Suggested structure:

```markdown
# Process Tap API — Discovery Notes (macOS 15)

Observed on: macOS <version> with Xcode <version> Swift <version>.

## Working calls

- `CATapDescription(stereoMixdownOfProcesses: [pid_t])` — confirmed/corrected: <actual signature found in probe>
- `description.exceptProcesses = [pid_t]` — confirmed
- `AudioHardwareCreateProcessTap(_ description: CATapDescription, _ outTapID: inout AudioObjectID) -> OSStatus` — confirmed
- `AudioHardwareCreateAggregateDevice(_ dictionary: CFDictionary, _ outDeviceID: inout AudioObjectID) -> OSStatus` — confirmed
- Aggregate-dictionary keys actually used: <list>
- Engine input device swap: `AudioUnitSetProperty` on `kAudioOutputUnitProperty_CurrentDevice` — confirmed

## Permission prompt

- First-run macOS prompt: <yes/no, and exact title text>
- Info.plist key required: <e.g. NSAudioCaptureUsageDescription, or none, or different>
- System Settings pane: <Privacy & Security → ???>

## Buffer format

- Sample rate: <e.g. 48000 Hz>
- Channels: <e.g. 2>
- Format: <e.g. Float32 interleaved/non-interleaved>

## Gotchas

- <any oddities — e.g., need to keep aggregate-device UID unique, teardown order matters, etc.>
```

Commit this file. The downstream tasks reference its findings.

- [ ] **Step 4: Commit**

```bash
git add Sources/Lorre/Core/Support/ProcessTapDiscoveryNotes.md
git commit -m "Document Process Tap API discovery notes (macOS 15)"
```

Note: do not commit `/tmp/process-tap-probe.swift` — it's local scratch.

---

## Task 2: Bump min macOS to 15.0

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Bump the platform**

Read `Package.swift`. Find:

```swift
    platforms: [
        .macOS(.v14)
    ],
```

Change to:

```swift
    platforms: [
        .macOS(.v15)
    ],
```

- [ ] **Step 2: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build
```

Expected: clean build. The existing ScreenCaptureKit code already requires macOS 14, so the bump is additive. If a build error mentions an API only available in 15.x, that's expected — we'll resolve in Task 4. For now expect clean.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "Bump min macOS deployment target to 15.0 (Sequoia)"
```

Note: this `Package.swift` change IS intentional and IS committed (unlike the tools-version workaround). Don't get confused with the toolchain-mismatch workaround.

---

## Task 3: ProcessTapSystemAudioCapture core

The new class that replaces SCStream-based system audio capture. Uses the API names verified in Task 1's discovery notes.

**Files:**
- Create: `Sources/Lorre/Core/Support/ProcessTapSystemAudioCapture.swift`

- [ ] **Step 1: Read discovery notes**

Open `Sources/Lorre/Core/Support/ProcessTapDiscoveryNotes.md` (from Task 1). The exact API names you use in this task MUST match what the discovery probe verified actually compiles and runs.

- [ ] **Step 2: Read existing system audio capture interface**

Open `Sources/Lorre/Core/Support/AVFoundationRecorderService.swift`. Find `SystemCaptureStartResult` (likely a private struct near the SCStream code). Note its fields — the new class must produce a result that fits the same shape so `AVFoundationRecorderService` can swap implementations transparently.

Also find `startSystemAudioCapture(filter:in:combinedMeter:previewBridge:previewMixer:source:)`. Note its parameters: `tempDir`, `combinedMeter: CombinedMeterBox?`, `previewBridge: LiveMonitorBridgeBox`, `previewMixer: MixedPreviewMixerBox?`, `source: RecordingSource`.

- [ ] **Step 3: Create the new file**

```swift
import Foundation
import AVFoundation
import CoreAudio
import os

/// Captures system audio from all running processes (except this process)
/// using macOS 15's CoreAudio Process Tap API. Wraps the tap in an aggregate
/// device so AVAudioEngine can pull buffers like any other input device.
///
/// Replaces the previous ScreenCaptureKit-based path. Permissions: the first
/// system-audio capture triggers a one-time macOS "Audio Recording" TCC prompt;
/// once granted, no further prompts and no SCContentSharingPicker dialog.
final class ProcessTapSystemAudioCapture {
    struct StartResult {
        let engine: AVAudioEngine
        let writer: SystemAudioWriter
        let outputURL: URL
        let startedAt: Date
    }

    private let logger = Logger(subsystem: "lorre", category: "ProcessTapSystemAudio")
    private var tapID: AudioObjectID?
    private var aggregateID: AudioObjectID?
    private var engine: AVAudioEngine?

    /// Build the tap + aggregate device + AVAudioEngine input wiring, install a
    /// tap on the input node, and start the engine. Returns engine and writer
    /// that the caller (`AVFoundationRecorderService`) owns for the lifetime
    /// of the recording.
    ///
    /// - Parameters:
    ///   - outputURL: where to write the .caf file (matches the previous SCStream output path).
    ///   - combinedMeter: optional meter box used in `Mic + System` mode.
    ///   - previewBridge: live monitor bridge for streaming partial transcripts.
    ///   - previewMixer: optional mixer used in `Mic + System` mode.
    func start(
        outputURL: URL,
        combinedMeter: CombinedMeterBox?,
        previewBridge: LiveMonitorBridgeBox,
        previewMixer: MixedPreviewMixerBox?
    ) async throws -> StartResult {
        // 1. CATapDescription: all processes except our PID, mono mixdown.
        let description = CATapDescription(stereoMixdownOfProcesses: [])
        description.processes = []
        description.exceptProcesses = [getpid()]
        description.muteBehavior = .unmuted
        description.isPrivate = false

        // 2. Create the process tap.
        var tap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr, tap != kAudioObjectUnknown else {
            throw LorreError.recordingStartFailed("Process tap creation failed (OSStatus \(tapStatus)).")
        }
        self.tapID = tap

        // 3. Wrap the tap in an aggregate device.
        let aggregateUID = "lorre.system-audio.aggregate.\(UUID().uuidString)"
        // The exact dictionary keys come from Task 1's discovery notes.
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceNameKey: "Lorre System Audio",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            // Add the tap-list key here. The exact name is verified in Task 1.
            // E.g., kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: String(tap)]]
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        let aggStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        guard aggStatus == noErr else {
            AudioHardwareDestroyProcessTap(tap)
            self.tapID = nil
            throw LorreError.recordingStartFailed("Aggregate device creation failed (OSStatus \(aggStatus)).")
        }
        self.aggregateID = aggregate

        // 4. Point AVAudioEngine's input at the aggregate device.
        let engine = AVAudioEngine()
        let inputUnit = engine.inputNode.audioUnit!
        var deviceID = aggregate
        let setStatus = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )
        guard setStatus == noErr else {
            AudioHardwareDestroyAggregateDevice(aggregate)
            AudioHardwareDestroyProcessTap(tap)
            self.tapID = nil
            self.aggregateID = nil
            throw LorreError.recordingStartFailed("Input device swap failed (OSStatus \(setStatus)).")
        }
        self.engine = engine

        // 5. Open the output file and install a tap that writes buffers + feeds previews.
        let format = engine.inputNode.inputFormat(forBus: 0)
        let writer = try SystemAudioWriter(outputURL: outputURL, format: format)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [logger] buffer, _ in
            do {
                try writer.write(buffer)
            } catch {
                logger.error("System audio writer failed: \(String(describing: error))")
            }
            combinedMeter?.acceptSystemAudio(buffer: buffer)
            previewMixer?.acceptSystemAudio(buffer: buffer)
            // Bridge live monitor so streaming transcription can see system audio
            // when no mic is involved.
            if previewMixer == nil {
                previewBridge.enqueueRecognitionBuffer(buffer)
            }
        }
        try engine.start()

        return StartResult(
            engine: engine,
            writer: writer,
            outputURL: outputURL,
            startedAt: Date()
        )
    }

    /// Stop the engine, remove the tap, destroy the aggregate + process tap.
    /// Safe to call multiple times; second call is a no-op.
    func stop() {
        if let engine = engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        self.engine = nil
        if let aggregate = aggregateID {
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        self.aggregateID = nil
        if let tap = tapID {
            AudioHardwareDestroyProcessTap(tap)
        }
        self.tapID = nil
    }

    deinit {
        stop()
    }
}

/// Writes incoming PCM buffers to a `.caf` file using AVAudioFile. Mirrors the
/// writer shape used by `SCStream`-based capture so the upstream service can
/// swap the producer without touching the consumer.
final class SystemAudioWriter {
    private let file: AVAudioFile

    init(outputURL: URL, format: AVAudioFormat) throws {
        // Match the previous CAF settings the ScreenCaptureKit writer used.
        // Verify by reading the old `startSystemAudioCapture` writer setup in
        // AVFoundationRecorderService.swift before this task; if it set explicit
        // settings (e.g., AVLinearPCMBitDepthKey, AVLinearPCMIsFloatKey),
        // pass those here. Otherwise default to AVAudioFile's format inference.
        self.file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        try file.write(from: buffer)
    }
}
```

**Verification before writing:**
- Open `AVFoundationRecorderService.swift` and locate the existing SCStream writer setup (likely calls `AVAssetWriter` or `AVAudioFile`). If it uses `AVAssetWriter` with specific output settings (e.g., `AVFormatIDKey: kAudioFormatLinearPCM`, sample rate override), copy those exact settings into `SystemAudioWriter.init`. If it uses `AVAudioFile` with `format.settings`, the snippet above is correct.
- If `CombinedMeterBox.acceptSystemAudio(buffer:)` or `MixedPreviewMixerBox.acceptSystemAudio(buffer:)` don't exist by those exact names, look at the SCStream callback in the current code and use whatever method names the existing meter/mixer boxes expose for system audio buffers.

- [ ] **Step 4: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build
```

Expected: clean build. The new class is not yet referenced from anywhere — Task 4 wires it up.

- [ ] **Step 5: Commit**

```bash
git add Sources/Lorre/Core/Support/ProcessTapSystemAudioCapture.swift
git commit -m "Add ProcessTapSystemAudioCapture for macOS 15 system audio"
```

---

## Task 4: Wire ProcessTapSystemAudioCapture into AVFoundationRecorderService

Replace every SCStream / SCContentSharingPicker reference with calls to the new actor. After this task, `import ScreenCaptureKit` is gone from `AVFoundationRecorderService.swift`.

**Files:**
- Modify: `Sources/Lorre/Core/Support/AVFoundationRecorderService.swift`

- [ ] **Step 1: Inventory the references**

```bash
grep -nE 'ScreenCaptureKit|SCStream|SCContent|ScreenCapturePickerObserverBox|pickSystemAudioFilter|#if canImport\(ScreenCaptureKit\)' Sources/Lorre/Core/Support/AVFoundationRecorderService.swift
```

This produces ~36 hits. Each hit needs to be removed or replaced.

- [ ] **Step 2: Delete all `#if canImport(ScreenCaptureKit)` guards and their content**

Within `AVFoundationRecorderService.swift`:

- Delete `#if canImport(ScreenCaptureKit) ... #endif` blocks and `#if canImport(ScreenCaptureKit) ... #else ... #endif` blocks (keep the `#else` body where it represents the "no system audio" path — but most #else branches throw an error; those can also be deleted because we now always have system audio support on macOS 15).
- Delete `import ScreenCaptureKit`, the `@preconcurrency import ScreenCaptureKit` line, the `import ScreenCaptureKit` typealiases.
- Delete the `ScreenCapturePickerObserverBox` class and any associated SCStream output handlers.
- Delete `pickSystemAudioFilter()` and `startSystemAudioCapture(filter:in:...)` private methods.
- Delete the `systemCapture: SCStream?` (or whatever the stored property is) — replace with `systemAudioCapture: ProcessTapSystemAudioCapture?`.
- Delete `SystemCaptureStartResult` — replace with `ProcessTapSystemAudioCapture.StartResult` (already provided in Task 3).

The grep from Step 1 should return zero results after the cleanup is complete.

- [ ] **Step 3: Replace the call site with ProcessTapSystemAudioCapture**

In `startRecording(_ request:)`, find this region (approximately the current `if request.source.includesSystemAudio, let filter = selectedFilter { ... systemStart = try await startSystemAudioCapture(...) ... }`).

Replace with:

```swift
let systemStart: ProcessTapSystemAudioCapture.StartResult?
if request.source.includesSystemAudio {
    let systemAudioTempURL = tempDir.appendingPathComponent("system-audio.caf")
    let processTap = ProcessTapSystemAudioCapture()
    systemStart = try await processTap.start(
        outputURL: systemAudioTempURL,
        combinedMeter: combinedMeter,
        previewBridge: monitorBridge,
        previewMixer: previewMixer
    )
    self.systemAudioCapture = processTap
} else {
    systemStart = nil
}
```

The `selectedFilter` indirection (which required picking a filter via SCContentSharingPicker before starting) goes away entirely. The new path starts the tap inline.

- [ ] **Step 4: Update the stop path**

Find `stopRecording()` (or `stop()`). In the current code there's a section like:

```swift
#if canImport(ScreenCaptureKit)
try? await systemCapture?.stopCapture()
self.systemCapture = nil
#endif
```

Replace with:

```swift
self.systemAudioCapture?.stop()
self.systemAudioCapture = nil
```

`ProcessTapSystemAudioCapture.stop()` is synchronous and safe to call multiple times (Task 3 guarantees this).

- [ ] **Step 5: Update `ensurePermissions(for:)` — only microphone check for now**

In `ensurePermissions(for source:)`, the current method only checks `.microphone`. With ScreenCaptureKit gone there's no screen-recording check to remove (the SCStream itself triggered the permission). The audio-recording TCC permission for Process Tap is handled by macOS itself when `AudioHardwareCreateProcessTap` is invoked — Task 5 will add a preflight wrapper for that. For this task, leave `ensurePermissions` as-is.

- [ ] **Step 6: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build
```

Expected: clean build, no warnings about unreferenced ScreenCaptureKit types. Run the grep from Step 1 again — should return **zero** hits.

- [ ] **Step 7: Run tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

Expected: 54/54 pass. The existing tests don't exercise the audio capture path, so they should be unaffected.

- [ ] **Step 8: Commit**

```bash
git add Sources/Lorre/Core/Support/AVFoundationRecorderService.swift
git commit -m "Swap ScreenCaptureKit out for ProcessTapSystemAudioCapture"
```

---

## Task 5: Add audio-recording permission preflight + Info.plist usage description

The Process Tap triggers a macOS TCC prompt the first time it's used. We want to (a) ensure the prompt is shown gracefully, (b) provide a clear usage-description string, and (c) handle the `denied` case with an open-settings deeplink, matching the existing microphone pattern.

**Files:**
- Modify: `Sources/Lorre/Core/Support/AVFoundationRecorderService.swift` (`ensurePermissions`)
- Modify: `scripts/package_macos_app.sh` (Info.plist generation — has a generated Info.plist; we add the new key)

- [ ] **Step 1: Inspect Info.plist generation**

```bash
grep -nE 'Info\.plist|NSMicrophoneUsageDescription|NSScreenCaptureUsageDescription|NSAudioCaptureUsageDescription' scripts/package_macos_app.sh
```

Identify where in the packaging script the Info.plist is created or copied. The script probably writes an Info.plist into the bundle.

- [ ] **Step 2: Add NSAudioCaptureUsageDescription**

Open `scripts/package_macos_app.sh`. Add an entry to the generated Info.plist for the audio-capture usage description. The exact key is verified in Task 1 — most likely `NSAudioCaptureUsageDescription`. The text should explain why Lorre needs to capture audio from other apps.

The shell-script pattern looks like (existing pattern for microphone):

```bash
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string 'Lorre uses your microphone to record voice for local transcription.'" "$INFO_PLIST"
```

Add an analogous line:

```bash
/usr/libexec/PlistBuddy -c "Add :NSAudioCaptureUsageDescription string 'Lorre captures audio from other apps so meetings and system audio can be transcribed locally.'" "$INFO_PLIST"
```

If the discovery notes (Task 1, Step 3) said a DIFFERENT key name is required (e.g., the API uses an undocumented internal TCC class with a different Info.plist key), use that key instead.

If there's also a NSScreenCaptureUsageDescription line in the script (legacy from the ScreenCaptureKit era), DELETE it — we no longer need that permission.

- [ ] **Step 3: Update `ensurePermissions(for:)` for audio-recording preflight**

In `Sources/Lorre/Core/Support/AVFoundationRecorderService.swift`, find:

```swift
private func ensurePermissions(for source: RecordingSource) async throws {
    if source.includesMicrophone, !(await requestMicrophonePermission()) {
        await MainActor.run {
            Self.openSystemSettings(for: .microphone)
        }
        throw LorreError.microphonePermissionDenied
    }
}
```

Extend it to also check audio-capture permission when system audio is needed:

```swift
private func ensurePermissions(for source: RecordingSource) async throws {
    if source.includesMicrophone, !(await requestMicrophonePermission()) {
        await MainActor.run {
            Self.openSystemSettings(for: .microphone)
        }
        throw LorreError.microphonePermissionDenied
    }

    if source.includesSystemAudio, !(await requestAudioCapturePermission()) {
        await MainActor.run {
            Self.openSystemSettings(for: .audioCapture)
        }
        throw LorreError.audioCapturePermissionDenied
    }
}

private func requestAudioCapturePermission() async -> Bool {
    // CoreAudio doesn't expose a synchronous "is this allowed?" query before the
    // first AudioHardwareCreateProcessTap call. Instead, we attempt a probe:
    // create a tiny tap, immediately destroy it, and observe success vs the
    // TCC-denied OSStatus (likely kAudioHardwareNoAccessError or similar — verify
    // via discovery notes).
    let description = CATapDescription(stereoMixdownOfProcesses: [])
    description.processes = []
    description.exceptProcesses = [getpid()]
    description.muteBehavior = .unmuted

    var probeTap = AudioObjectID(kAudioObjectUnknown)
    let status = AudioHardwareCreateProcessTap(description, &probeTap)
    if status == noErr {
        AudioHardwareDestroyProcessTap(probeTap)
        return true
    }
    // Any non-success status means we couldn't create the tap. Most commonly
    // this is a permission denial (TCC) or the user hasn't yet granted access.
    // macOS shows its own permission prompt the first time, so if the user
    // hasn't decided yet they'll see it during this probe call.
    return false
}
```

Note: if Task 1's discovery established that `AudioHardwareCreateProcessTap` DOES trigger the system prompt automatically, this probe approach works. If discovery found a different prompt-triggering API (e.g., a `requestAccess`-style function on a new audio-recording class), use that instead.

Add the corresponding error case + settings pane to the existing `LorreError` and `PermissionSettingsPane` enums:

```swift
// In LorreError:
case audioCapturePermissionDenied

// In PermissionSettingsPane:
case audioCapture

// In openSystemSettings(for:):
case .audioCapture:
    candidateURLs = [
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture"),
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
    ].compactMap { $0 }
```

The exact deep-link URL for the audio-capture pane is verified at run time. If neither URL opens the pane, the fallback `_ = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))` will at least open Settings.

User-facing error message: open `Sources/Lorre/Core/Support/UserFacingErrorMapper.swift` and add a mapping for `audioCapturePermissionDenied` mirroring the existing `microphonePermissionDenied` mapping. Text suggestion: "Lorre needs permission to record audio from other apps. Grant access in System Settings → Privacy & Security → Audio Recording, then try again."

- [ ] **Step 4: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build
```

Expected: clean.

- [ ] **Step 5: Run tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

Expected: 54/54 pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Lorre/Core/Support/AVFoundationRecorderService.swift Sources/Lorre/Core/Support/UserFacingErrorMapper.swift scripts/package_macos_app.sh
git commit -m "Add audio-recording permission preflight + usage description"
```

---

## Task 6: Full verification

End-to-end test of the new capture path with real audio + permission grant + Settings → Privacy pane check.

**Files:** (none — manual verification)

- [ ] **Step 1: Full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

Expected: 54/54 pass.

- [ ] **Step 2: Build release .app**

```bash
./scripts/package_macos_app.sh release
```

Expected: `dist/Lorre.app` produced with the updated Info.plist (includes `NSAudioCaptureUsageDescription`, omits any `NSScreenCaptureUsageDescription`).

Verify by:

```bash
plutil -p dist/Lorre.app/Contents/Info.plist | grep -E 'Microphone|AudioCapture|ScreenCapture'
```

Expected:
- `NSMicrophoneUsageDescription` present
- `NSAudioCaptureUsageDescription` present
- `NSScreenCaptureUsageDescription` absent

- [ ] **Step 3: Install and grant permissions**

```bash
rm -rf /Applications/Lorre.app
cp -R dist/Lorre.app /Applications/
open /Applications/Lorre.app
```

In System Settings → Privacy & Security:
- Remove any existing **Screen Recording** entry for Lorre (manual cleanup of the legacy permission)
- Open **Audio Recording** (or "Audio Capture" — whichever pane macOS shows). Lorre will appear here after the first system-audio recording attempt and prompt.

- [ ] **Step 4: Acceptance check — microphone-only recording**

In Lorre toolbar, select **Mic**. Start a recording, speak for 5 seconds, stop.

Expected:
- Mic permission prompt (if not previously granted)
- **No** audio-recording prompt
- **No** SCContentSharingPicker dialog
- Session appears in sidebar with valid transcript

- [ ] **Step 5: Acceptance check — system-audio recording**

Play music from another app (Spotify, Music, browser tab). Select **System** in the Lorre toolbar. Start a recording, let it run for 10 seconds, stop.

Expected:
- One-time **audio-recording permission prompt** (if first run). Grant it.
- **No** Screen Recording permission prompt
- **No** SCContentSharingPicker dialog
- Session appears in sidebar with a transcript of the music's lyrics (or audio content)
- Captured `.caf` file is valid (open in QuickTime to verify)

- [ ] **Step 6: Acceptance check — mic + system**

Select **Mic + System**. Start a recording, speak over background music, stop.

Expected:
- No additional prompts (both permissions already granted)
- Both mic stem and system-audio stem in the session
- Transcript shows both your voice and the system audio content

- [ ] **Step 7: Confirm Screen Recording permission is gone**

Open System Settings → Privacy & Security → Screen Recording. Lorre should not appear (or should be safe to remove — it's no longer required).

- [ ] **Step 8: Confirm permission persistence**

Quit Lorre, restart. Start a system-audio recording again. Expected: no permission prompt this time — TCC remembers the grant.

If everything in Steps 1–8 passes, the migration is complete.

---

## Out of plan

Per the spec, these are explicitly NOT in this sub-project:
- UI changes (source segmented control, Settings, anything visual)
- Per-app process picker (a UI to select which specific app to tap)
- Microphone capture refactoring
- Import-audio refactoring
- Sub-projects B and C (sidebar native chrome / pane visual polish)

If anything outside this scope comes up during implementation, file as a follow-up and don't expand the plan inline.
