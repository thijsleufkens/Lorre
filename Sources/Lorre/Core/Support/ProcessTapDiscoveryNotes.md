# Process Tap API — Discovery Notes (macOS 15)

Observed on: macOS 15.7.3 (Build 24G419) with Xcode 26.3 (Build 17C529),
Swift 6.2.4 (swiftlang-6.2.4.1.4).

Probe file: `/tmp/process-tap-probe.swift` (not committed — local scratch only).

---

## Working calls

### `CATapDescription` initializer

**ObjC header** (`CATapDescription.h`):
```objc
- (instancetype) initStereoGlobalTapButExcludeProcesses:(NSArray<NSNumber*>*)processesObjectIDsToExcludeFromTap NS_REFINED_FOR_SWIFT;
```

**Swift name** (from `CoreAudio.swiftmodule/arm64e-apple-macos.swiftinterface`):
```swift
// Requires macOS 14.0
CATapDescription(stereoGlobalTapButExcludeProcesses: [AudioObjectID])
```

This is the correct initializer for "capture all system audio except the listed processes". The argument type is `[AudioObjectID]`, not `[pid_t]`.

Other confirmed Swift initializers (all `@available(macOS 14.0, ...)`):
- `CATapDescription(stereoMixdownOfProcesses: [AudioObjectID])` — include only listed
- `CATapDescription(monoMixdownOfProcesses: [AudioObjectID])` — mono, include only listed
- `CATapDescription(monoGlobalTapButExcludeProcesses: [AudioObjectID])` — mono, exclude listed
- `CATapDescription(processes: [AudioObjectID], deviceUID: String, stream: UInt)` — target specific device stream
- `CATapDescription(excludingProcesses: [AudioObjectID], deviceUID: String, stream: UInt)` — exclude, target device stream

`CATapDescription` class itself is `@available(macOS 12.0, iOS 15.0)`, but the Swift convenience initializers require macOS 14.0.

### `CATapDescription` properties

| Property | ObjC name | Swift name | Notes |
|---|---|---|---|
| Mute behavior | `muteBehavior` (setter) | `.muteBehavior = CATapMuteBehavior` | `.unmuted` = 0 (default), `.muted` = 1, `.mutedWhenTapped` = 2 |
| Private tap | `setPrivate:` (setter) | `.isPrivate = Bool` | **`privateTap` was obsoleted in Swift 3** — use `.isPrivate` |
| Exclusive (exclude mode) | `exclusive` (getter `isExclusive`) | `.isExclusive` | Set by using the `exclude` initializers |
| Mono | `mono` (getter `isMono`) | `.isMono` | Set by using mono initializers |
| Processes | `processes` (NS_REFINED_FOR_SWIFT) | `.processes: [AudioObjectID]` | ObjectIDs, not PIDs |
| Bundle IDs | `bundleIDs` | `.bundleIDs: [String]` | `@available(macOS 26.0)` — not yet usable |
| Process restore | `processRestoreEnabled` | `.isProcessRestoreEnabled` | `@available(macOS 26.0)` — not yet usable |

### Getting a process's `AudioObjectID` from a PID

`CATapDescription` initializers take `[AudioObjectID]`, not `[pid_t]`. To translate a PID:

```swift
// 1. Get list of process AudioObjectIDs from the system object
var address = AudioObjectPropertyAddress(
    mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyProcessObjectList),  // 'prs#'
    mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
    mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
)
var dataSize: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
var objectIDs = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &objectIDs)

// 2. For each, query kAudioProcessPropertyPID ('ppid')
for objectID in objectIDs {
    var pidAddress = AudioObjectPropertyAddress(
        mSelector: AudioObjectPropertySelector(kAudioProcessPropertyPID),
        mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
        mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    )
    var processPID: pid_t = 0
    var pidSize = UInt32(MemoryLayout<pid_t>.size)
    let s = AudioObjectGetPropertyData(objectID, &pidAddress, 0, nil, &pidSize, &processPID)
    if s == noErr && processPID == targetPID { return objectID }
}
```

There is also a high-level Swift API (`AudioHardwareSystem.shared.process(for: pid_t)`) but it is guarded by `#if compiler(>=5.3) && $NonescapableTypes` in the .swiftinterface — uncertain availability; the C-property approach above is reliable.

### `AudioHardwareCreateProcessTap`

**Signature (C)**:
```c
extern OSStatus
AudioHardwareCreateProcessTap(CATapDescription* inDescription,
                               AudioObjectID*  outTapID)
    API_AVAILABLE(macos(14.2));
```

**Swift call**:
```swift
var tapID = AudioObjectID(kAudioObjectUnknown)
let status = AudioHardwareCreateProcessTap(description, &tapID)
```

Confirmed working: returns `noErr` (0) and a valid non-`kAudioObjectUnknown` tap ID.

### Getting the tap's UID string

After creation, query `kAudioTapPropertyUID` ('tuid') on the tap object to get the CFString UID needed for the aggregate device's tap list:

```swift
var address = AudioObjectPropertyAddress(
    mSelector: AudioObjectPropertySelector(kAudioTapPropertyUID),  // 'tuid'
    mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
    mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
)
var uid: CFString? = nil
var dataSize = UInt32(MemoryLayout<CFString?>.size)
AudioObjectGetPropertyData(tapObjectID, &address, 0, nil, &dataSize, &uid)
// uid is now a UUID string like "CD72E4B3-7F42-4E4C-93AE-F63B3585B0F2"
```

Note: Swift 6 emits a warning ("forming UnsafeMutableRawPointer to Optional<CFString>") for this
pattern. Use an Unmanaged<CFString> approach or bridge via withUnsafeMutableBytes to silence it
in production code. The probe's approach works at runtime.

### `AudioHardwareCreateAggregateDevice`

**Signature (C)**:
```c
extern OSStatus
AudioHardwareCreateAggregateDevice(CFDictionaryRef inDescription, AudioObjectID* outDeviceID);
```

**Aggregate device dictionary keys** (all `String` constants from `AudioHardware.h`):

| Constant | Raw string | Value type | Notes |
|---|---|---|---|
| `kAudioAggregateDeviceUIDKey` | `"uid"` | String | Unique ID for the aggregate |
| `kAudioAggregateDeviceNameKey` | `"name"` | String | Human-readable name |
| `kAudioAggregateDeviceTapListKey` | `"taps"` | `[[String: Any]]` | Array of sub-tap dicts |
| `kAudioAggregateDeviceIsPrivateKey` | `"private"` | Int (0 or 1) | **Must be 1** for tap-only aggregates |
| `kAudioAggregateDeviceIsStackedKey` | `"stacked"` | Int (0 or 1) | 0 for tap aggregate |
| `kAudioAggregateDeviceTapAutoStartKey` | `"tapautostart"` | Int (0 or 1) | Optional: wait for first audio before start; must also set private=1 |

**Sub-tap dictionary key**:

| Constant | Raw string | Value type |
|---|---|---|
| `kAudioSubTapUIDKey` | `"uid"` | String (the tap's UID from `kAudioTapPropertyUID`) |

**Working example**:
```swift
let tapList: [[String: Any]] = [
    [kAudioSubTapUIDKey: tapUID]   // tapUID = String from kAudioTapPropertyUID
]
let aggregateDescription: [String: Any] = [
    kAudioAggregateDeviceUIDKey:  aggregateUID,         // unique String, e.g. "lorre.aggregate.<UUID>"
    kAudioAggregateDeviceNameKey: "Lorre System Audio",
    kAudioAggregateDeviceTapListKey: tapList,
    kAudioAggregateDeviceIsPrivateKey: 1,
    kAudioAggregateDeviceIsStackedKey: 0
]
var aggregateID = AudioObjectID(kAudioObjectUnknown)
let status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
```

### Engine input device swap

```swift
let engine = AVAudioEngine()
let inputUnit = engine.inputNode.audioUnit!
var deviceID = aggregateID
AudioUnitSetProperty(
    inputUnit,
    kAudioOutputUnitProperty_CurrentDevice,
    kAudioUnitScope_Global,
    0,
    &deviceID,
    UInt32(MemoryLayout<AudioObjectID>.size)
)
```

Confirmed working. Must be called **before** `engine.start()`.

### `AudioHardwareDestroyProcessTap` / `AudioHardwareDestroyAggregateDevice`

```c
extern OSStatus AudioHardwareDestroyProcessTap(AudioObjectID inTapID)
    API_AVAILABLE(macos(14.2));

extern OSStatus AudioHardwareDestroyAggregateDevice(AudioObjectID inDeviceID);
```

Both confirmed working. Teardown order: destroy aggregate device **before** destroying the tap.

---

## Permission prompt

- **First-run macOS prompt**: No prompt was observed during the probe run. The `xcrun swift` CLI
  interpreter already had microphone/audio access granted on this machine from a prior Lorre build.
- **TCC service**: Process Tap uses the **Microphone** TCC service
  (`kTCCServiceMicrophone` / `NSMicrophoneUsageDescription`), not a dedicated "Audio Recording" or
  "Screen Recording" class.
- **Info.plist key required**: `NSMicrophoneUsageDescription` — same key as standard microphone
  recording. Lorre already has this key:
  ```xml
  <key>NSMicrophoneUsageDescription</key>
  <string>Lorre needs microphone access to record audio locally.</string>
  ```
  This description should be updated for Task 5 to also mention system audio capture.
- **System Settings pane**: Privacy & Security → **Microphone**
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`)
- **No new Info.plist key** is required for Process Tap beyond `NSMicrophoneUsageDescription`.
- **No separate entitlement** was required for the `xcrun swift` CLI probe. Sandboxed app store
  builds may require `com.apple.security.device.audio-input`.

---

## Buffer format

From `engine.inputNode.inputFormat(forBus: 0)` and `kAudioTapPropertyFormat`:

| Property | Value |
|---|---|
| Sample rate | 48,000 Hz |
| Channels | 2 (stereo) |
| Bit depth | 32-bit |
| Format ID | `lpcm` (Linear PCM, `kAudioFormatLinearPCM`) |
| Layout | **Non-interleaved** (deinterleaved / planar) |
| Swift type | `AVAudioFormat` → `<AVAudioFormat: 2 ch, 48000 Hz, Float32, deinterleaved>` |

Buffer timing: with `bufferSize: 4096`, AVAudioEngine delivers buffers of 4,800 frames each at
48 kHz. In 2 seconds of capture: **19 buffers** (≈ 10 Hz callback rate, ~100 ms per buffer).

---

## Gotchas

1. **`privateTap` property name obsoleted**: The ObjC property `privateTap` was renamed to
   `isPrivate` in Swift. Using `description.privateTap = false` causes a compile error:
   ```
   error: 'privateTap' has been renamed to 'isPrivate'
   ```
   Use `description.isPrivate = false` (or `true`).

2. **`CATapDescription` argument type is `[AudioObjectID]`, not `[pid_t]`**: The skeleton in the
   task spec uses `description.exceptProcesses = [myPID]` — this property does not exist.
   The Swift initializers take `[AudioObjectID]` and you must translate PIDs via
   `kAudioHardwarePropertyProcessObjectList` + `kAudioProcessPropertyPID`.

3. **Tap UID bridging warning**: Using `CFString?` with `AudioObjectGetPropertyData` emits a
   Swift 6 compiler warning about forming `UnsafeMutableRawPointer` to an object reference.
   Production code should use `withUnsafeMutableBytes` or `Unmanaged<CFString>` to bridge safely.

4. **`AudioHardwareTapping.h` requires `__OBJC__`**: The header is wrapped in
   `#ifdef __OBJC__` / `#endif` — it is only included when compiling as Objective-C or with the
   ObjC bridge. In a Swift file that imports `CoreAudio`, this is handled transparently by the
   clang importer.

5. **`#if compiler(>=5.3) && $NonescapableTypes` guards**: The high-level Swift API
   (`AudioHardwareSystem.shared.makeProcessTap(description:)`,
   `AudioHardwareSystem.shared.process(for: pid_t)`, etc.) is conditionally available based on
   a compiler feature flag (`$NonescapableTypes`). Whether this is available at runtime depends on
   the Swift toolchain version. Prefer the C API (`AudioHardwareCreateProcessTap`) for production
   code to avoid this uncertainty.

6. **`kAudioAggregateDeviceIsPrivateKey: 1` is important**: Omitting this or setting it to 0
   may make the aggregate device visible to other applications, which is undesirable. For
   `kAudioAggregateDeviceTapAutoStartKey`, the docs require `private: 1` as well.

7. **Teardown order matters**: Destroy the aggregate device before destroying the tap. Reversing
   this order may cause the aggregate device to reference a destroyed tap object.

8. **`CATapDescription.init()` (no-args) has `isPrivate = true` by default**: The plain
   `CATapDescription()` initializer sets `isPrivate = true` (confirmed). Explicitly set
   `isPrivate = false` if you want the tap visible to other processes.

9. **`bundleIDs` and `isProcessRestoreEnabled` are macOS 26.0 only**: These new properties
   (which allow tapping by bundle ID string and auto-restoring taps across process restarts)
   are not available on macOS 15. Do not use them in Task 3.

10. **API availability summary**:
    - `CATapDescription` class: `macOS 12.0`
    - `CATapMuteBehavior` enum: `macOS 13.0`
    - Swift convenience initializers (`stereoGlobalTapButExcludeProcesses` etc.): **`macOS 14.0`**
    - `AudioHardwareCreateProcessTap` / `AudioHardwareDestroyProcessTap`: **`macOS 14.2`**
    - `AudioHardwareAggregateDevice` + `AudioHardwareSystem` Swift classes: **`macOS 15.0`**

    For Lorre's min-deployment of macOS 15.0 (after Task 2 bumps it), all of the above are
    available without conditional checks.
