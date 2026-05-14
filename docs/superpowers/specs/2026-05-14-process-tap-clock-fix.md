# Process Tap — clock-source fix voor system-audio capture

**Status:** implemented — verified working on macOS 15.7.3 ad-hoc signed build
**Date:** 2026-05-14
**Branch:** `claude/process-tap-system-audio` (voortzetting van eerdere Process Tap migratie)

> **Update (post-implementation):** Tijdens uitvoering bleek dat de aggregate-clock + IOProc fix uit deze spec niet voldoende was. De tap leverde nog steeds 0-buffers, ook in mic+system mode. Twee aanvullende oorzaken werden gevonden tegen AudioCap als referentie:
>
> 1. **Process include list moet gefilterd zijn op `kAudioProcessPropertyIsRunningOutput`** — het meegeven van alle inactieve processen breekt de tap stilletjes. Alleen apps die op het moment van Start ook daadwerkelijk audio outputten worden meegenomen.
> 2. **Code-signing entitlement + Info.plist key zijn vereist**, ook bij ad-hoc signing: `com.apple.security.device.audio-input` als entitlement én `NSAudioCaptureUsageDescription` in Info.plist. Zonder beide vuurt de IOProc, schrijft AVAudioFile data, maar bevat elke buffer 100% nullen.
>
> CLAUDE.md is bijgewerkt om de oorspronkelijke conclusie ("Process Tap gated on Developer ID") te corrigeren. `scripts/package_macos_app.sh` past de entitlement en plist key nu automatisch toe bij iedere build.

## Doel

De Process Tap implementatie op branch `claude/process-tap-system-audio` (commit 7bd4cba) capture-t **geen** audio wanneer source = **System only**. Dezelfde code werkt wel wanneer source = **Mic + System** of **Mic only**. Het bestaande oordeel ("Process Tap silently produces zero buffers in ad-hoc-signed builds" — uit `CLAUDE.md`) is een misdiagnose: ad-hoc signing is niet de blokkade. De daadwerkelijke bug zit in de aggregate-device-config en de leesmethode.

Fix de tap door (1) de aggregate device een echte hardware-clock te geven (het default system output device), en (2) PCM-buffers te lezen via `AudioDeviceCreateIOProcIDWithBlock` in plaats van `AVAudioEngine` + `installTap`. Dit is exact het pattern dat [insidegui/AudioCap](https://github.com/insidegui/AudioCap) gebruikt — de canonieke macOS 14.4+ tap-referentie die bewezen werkt onder ad-hoc signing.

## Scope

**In scope**
- `Sources/Lorre/Core/Support/ProcessTapSystemAudioCapture.swift` herschrijven volgens AudioCap-pattern.
- Nieuwe private helper: lookup default system output device (`kAudioHardwarePropertyDefaultSystemOutputDevice` → `kAudioDevicePropertyDeviceUID`).
- Aggregate device dictionary uitbreiden met `kAudioAggregateDeviceMainSubDeviceKey`, `kAudioAggregateDeviceSubDeviceListKey`, `kAudioAggregateDeviceTapAutoStartKey: true`, en `kAudioSubTapDriftCompensationKey: true` in de tap-entry.
- AVAudioEngine + `installTap` vervangen door `AudioDeviceCreateIOProcIDWithBlock` + `AudioDeviceStart` op de aggregate.
- IOProc callback wrapt `AudioBufferList` → `AVAudioPCMBuffer` met format uit `kAudioTapPropertyFormat`; bestaande `ProcessTapAudioWriter`, meter-callback en preview-PCM-callback blijven ongewijzigd.
- Teardown-volgorde aangepast: `AudioDeviceStop` → `AudioDeviceDestroyIOProcID` → `AudioHardwareDestroyAggregateDevice` → `AudioHardwareDestroyProcessTap`.
- Conversie naar canonical format (Float32, 48 kHz, 2-ch, non-interleaved) blijft via `RecorderAudioUtilities.convert` indien tap-format afwijkt.

**Out of scope**
- Microfoon-pad (`startMicrophoneCapture`) — onveranderd.
- Stem-mixing / `combineStereoOrMonoStems` — onveranderd; format en bestandsindeling blijven gelijk.
- Live preview / streaming transcription pipeline — onveranderd, krijgt dezelfde PCM-callbacks.
- Recovery van het "zero buffers after long session"-probleem uit [Apple forum #825780](https://developer.apple.com/forums/thread/825780). Apart te adresseren als monitoring + teardown-and-rebuild — geen blocker voor deze fix.
- Per-app process picker. Tap blijft `stereoGlobalTapButExcludeProcesses` met alleen onze eigen PID.
- Schema-versies, persistence-formaten, Info.plist (al correct sinds commit 7bd4cba).
- Bumping naar macOS 26 / nieuwe `bundleIDs`/`processRestoreEnabled` APIs.

## Achtergrond — waarom de huidige implementatie alleen in mic+system werkt

Huidige aggregate (`ProcessTapSystemAudioCapture.swift:178-186`):

```swift
let aggregateDescription: [String: Any] = [
    kAudioAggregateDeviceUIDKey: aggregateUID,
    kAudioAggregateDeviceNameKey: "Lorre System Audio",
    kAudioAggregateDeviceTapListKey: tapList,
    kAudioAggregateDeviceIsPrivateKey: 1,
    kAudioAggregateDeviceIsStackedKey: 0
]
```

Geen `kAudioAggregateDeviceMainSubDeviceKey`, geen sub-device list, geen `tapautostart`. Dit is een "tap-only aggregate" zonder fysieke audio-hardware in z'n samenstelling. Een aggregate heeft een hardware-klok nodig om z'n I/O-cyclus te pompen — een tap zelf levert geen klok, het levert alleen audio-data wanneer een I/O-cyclus elders het opvraagt.

Leespad (`ProcessTapSystemAudioCapture.swift:200-244`):

```swift
let engine = AVAudioEngine()
let inputUnit = engine.inputNode.audioUnit!
var deviceID: AudioDeviceID = aggregateID
AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_CurrentDevice, ...)
engine.inputNode.installTap(onBus: 0, ...) { buffer, _ in ... }
try engine.start()
```

`AVAudioEngine` wil een echt input-device met een werkende I/O cycle. Op een tap-only aggregate zonder klok geeft `engine.start()` niet expliciet een fout, maar de input-tap-callback wordt nooit (of met zero-buffers) aangeroepen.

**Waarom het symptoom precies past:**
- **Mic only** → tap is helemaal niet betrokken; werkt.
- **System only** → tap-only aggregate, geen klok, geen I/O cycle, zero buffers.
- **Mic + system** → de aparte microfoon-`AVAudioEngine` houdt de CoreAudio I/O loop draaiend; de tap-aggregate krijgt daardoor net genoeg I/O cycles om buffers te leveren. Werkt wankel — kans op drift en gemiste samples bij hoge load, maar functioneel.

[AudioCap](https://github.com/insidegui/AudioCap) en gerelateerde voorbeelden ([sudara gist](https://gist.github.com/sudara/34f00efad69a7e8ceafa078ea0f76f6f), [audiotee](https://github.com/makeusabrew/audiotee)) gebruiken altijd `AudioDeviceCreateIOProcID(WithBlock)` directe op de aggregate, niet `AVAudioEngine`. AudioCap voegt daarnaast het system output device toe als `MainSubDevice` zodat de aggregate een echte hardware-klok heeft.

## Componenten

### `ProcessTapSystemAudioCapture.swift` — herschreven structuur

Public interface ongewijzigd:

```swift
@available(macOS 15.0, *)
final class ProcessTapSystemAudioCapture: @unchecked Sendable {
    struct StartResult { let outputURL: URL; let startedAt: Date }
    func start(outputURL:onPCMBuffer:onMeterLevel:) async throws -> StartResult
    func stop()
    func writeFailure() -> String?
}
```

Intern verandert:

```swift
private let lock = NSLock()
private var tapID: AudioObjectID?
private var aggregateID: AudioObjectID?
private var ioProcID: AudioDeviceIOProcID?
private var writer: ProcessTapAudioWriter?
private var inputFormat: AVAudioFormat?
private let ioQueue = DispatchQueue(label: "Lorre.ProcessTap.IO", qos: .userInteractive)
```

Geen `AVAudioEngine` property meer.

### Aggregate device — nieuwe dictionary

```swift
let outputUID = try queryDefaultSystemOutputDeviceUID()

let aggregateDescription: [String: Any] = [
    kAudioAggregateDeviceUIDKey:         "lorre.process-tap.\(UUID().uuidString)",
    kAudioAggregateDeviceNameKey:        "Lorre System Audio",
    kAudioAggregateDeviceIsPrivateKey:   true,
    kAudioAggregateDeviceIsStackedKey:   false,
    kAudioAggregateDeviceTapAutoStartKey: true,
    kAudioAggregateDeviceMainSubDeviceKey: outputUID,
    kAudioAggregateDeviceSubDeviceListKey: [
        [kAudioSubDeviceUIDKey: outputUID]
    ],
    kAudioAggregateDeviceTapListKey: [
        [
            kAudioSubTapUIDKey:                tapUID,
            kAudioSubTapDriftCompensationKey:  true
        ]
    ]
]
```

### Default system output device lookup — nieuwe private helper

```swift
private func queryDefaultSystemOutputDeviceUID() throws -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultSystemOutputDevice),
        mScope:    AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
        mElement:  AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    )
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    )
    guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
        throw LorreError.recordingStartFailed(
            "Could not resolve default system output device (status: \(status))."
        )
    }
    return try queryDeviceUID(deviceID: deviceID)
}

private func queryDeviceUID(deviceID: AudioObjectID) throws -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceUID),
        mScope:    AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
        mElement:  AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    )
    var unmanagedUID: Unmanaged<CFString>? = nil
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutableBytes(of: &unmanagedUID) { rawPtr in
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, rawPtr.baseAddress!)
    }
    guard status == noErr, let unmanaged = unmanagedUID else {
        throw LorreError.recordingStartFailed(
            "Could not query device UID (status: \(status))."
        )
    }
    return unmanaged.takeRetainedValue() as String
}
```

### Tap input format — uit `kAudioTapPropertyFormat`

In plaats van `engine.inputNode.inputFormat(forBus: 0)`:

```swift
private func queryTapStreamFormat(tapObjectID: AudioObjectID) throws -> AVAudioFormat {
    var address = AudioObjectPropertyAddress(
        mSelector: AudioObjectPropertySelector(kAudioTapPropertyFormat),
        mScope:    AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
        mElement:  AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    )
    var asbd = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    let status = AudioObjectGetPropertyData(tapObjectID, &address, 0, nil, &size, &asbd)
    guard status == noErr else {
        throw LorreError.recordingStartFailed(
            "Could not query tap format (status: \(status))."
        )
    }
    guard let format = AVAudioFormat(streamDescription: &asbd) else {
        throw LorreError.recordingStartFailed("Tap format is not valid PCM.")
    }
    return format
}
```

### IO Proc — vervangt installTap

```swift
let tapFormat = try queryTapStreamFormat(tapObjectID: tapID)
let writerFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 48_000,
    channels: 2,
    interleaved: false
)!
let writer = try ProcessTapAudioWriter(outputURL: outputURL, format: writerFormat)

var procID: AudioDeviceIOProcID?
let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
    &procID,
    aggregateID,
    ioQueue
) { [weak writer] _, inputData, _, _, _ in
    guard let writer else { return }
    guard let pcmBuffer = AVAudioPCMBuffer(
        pcmFormat: tapFormat,
        bufferListNoCopy: inputData,
        deallocator: nil
    ) else { return }

    let canonical: AVAudioPCMBuffer
    if pcmBuffer.format == writerFormat {
        canonical = pcmBuffer
    } else if let converted = try? RecorderAudioUtilities.convert(pcmBuffer, to: writerFormat) {
        canonical = converted
    } else {
        return
    }

    writer.write(canonical)
    onMeterLevel(canonical.lorre_meterLevel())
    onPCMBuffer(canonical)
}

guard ioStatus == noErr, let procID else {
    throw LorreError.recordingStartFailed(
        "AudioDeviceCreateIOProcIDWithBlock failed (status: \(ioStatus))."
    )
}

let startStatus = AudioDeviceStart(aggregateID, procID)
guard startStatus == noErr else {
    AudioDeviceDestroyIOProcID(aggregateID, procID)
    throw LorreError.recordingStartFailed(
        "AudioDeviceStart failed (status: \(startStatus))."
    )
}
```

### Teardown — nieuwe volgorde

`stop()` houdt dezelfde public contract (idempotent), maar interne sequence:

```
1. AudioDeviceStop(aggregateID, procID)
2. AudioDeviceDestroyIOProcID(aggregateID, procID)
3. AudioHardwareDestroyAggregateDevice(aggregateID)  ← aggregate vóór tap (discovery gotcha #7)
4. AudioHardwareDestroyProcessTap(tapID)
5. writer?.finish()
```

### `AVFoundationRecorderService.swift`

**Geen wijzigingen.** De call-site (`processTap.start(outputURL:onPCMBuffer:onMeterLevel:)`) en de `writeFailure()`-polling blijven exact zoals nu in commit 098897c.

## Acceptance criteria

- [ ] `Sources/Lorre/Core/Support/ProcessTapSystemAudioCapture.swift` gebruikt `AudioDeviceCreateIOProcIDWithBlock` + `AudioDeviceStart`. Geen `AVAudioEngine`, geen `installTap`, geen `kAudioOutputUnitProperty_CurrentDevice` meer in dit bestand.
- [ ] De aggregate device dictionary bevat `kAudioAggregateDeviceMainSubDeviceKey`, `kAudioAggregateDeviceSubDeviceListKey` (met het default system output device UID), `kAudioAggregateDeviceTapAutoStartKey: true`, en de tap-entry bevat `kAudioSubTapDriftCompensationKey: true`.
- [ ] Recording met source = **System audio** levert een `.caf` bestand op dat hoorbare audio bevat (afspelen via `afplay` of QuickTime). Niet 0 bytes, niet pure stilte, geen "0 hz" warning.
- [ ] Recording met source = **Microphone** blijft werken (gedrag onveranderd; tap pad wordt niet aangeroepen).
- [ ] Recording met source = **Microphone + System** blijft werken; mic-stem en system-stem worden los opgeslagen en gemixt zoals nu.
- [ ] Stop tijdens een actieve system-only recording laat geen tap of aggregate device achter (`AudioObjectGetPropertyData` op `kAudioHardwarePropertyDevices` toont geen `Lorre System Audio` device meer; `kAudioHardwarePropertyProcessObjectList` heeft geen weeskinderen).
- [ ] Cancel tijdens een actieve recording (vóór de eerste buffer) ruimt zowel tap als aggregate op.
- [ ] Permission-flow ongewijzigd: eerste keer system-audio recording triggert de macOS Microphone TCC prompt (`NSMicrophoneUsageDescription`). Geen Screen Recording prompt, geen `SCContentSharingPicker` dialog.
- [ ] Captured `.caf` heeft hetzelfde formaat als vóór de fix: Float32, 48 kHz, 2-ch (non-interleaved zoals geschreven door `AVAudioFile`). Bestaande sessies blijven afspeelbaar.
- [ ] Live transcription / preview blijft werken tijdens system-only recording (de `onPCMBuffer` callback wordt nu daadwerkelijk aangeroepen).
- [ ] Alle 54 bestaande tests blijven groen. Geen nieuwe tests voor de tap-logica zelf (audio capture is — net als nu — handmatig getest, niet via XCTest).
- [ ] CLAUDE.md update: de paragraaf onder "Architecture in one breath" die zegt *"Do not re-attempt Process Tap migration without a Developer ID"* wordt vervangen door een korte note dat de eerdere conclusie incorrect was, en dat de werkende implementatie nu de AudioCap-aggregate-with-output-clock + IOProc pattern volgt.
- [ ] Niets in `Sources/` importeert nog `ScreenCaptureKit` of refereert aan `SCStream*` / `SCContentFilter*` / `SCContentSharingPicker*` (zou al weg moeten zijn sinds commit 098897c — verifiëren).

## Risico's

1. **Default output device wijzigt tijdens recording.** Als de user mid-recording een AirPods koppelt of een ander output device kiest, blijft de aggregate naar het oude device wijzen → buffers stoppen of worden uit de verkeerde stream getrokken. Mitigatie v1: documenteren als bekende limitatie, behavior matchen aan AudioCap (geen auto-relink). Mitigatie v2 (later): listener op `kAudioHardwarePropertyDefaultSystemOutputDevice` + teardown/rebuild van aggregate. Geen blocker voor deze fix.
2. **Zero-buffer-after-long-session bug ([Apple forum #825780](https://developer.apple.com/forums/thread/825780)).** Op macOS 26.5 beta is gerapporteerd dat een tap na 7+ minuten plots zero-buffers gaat leveren. Niet gereproduceerd op macOS 15.7.3 dat Lorre target, maar het is een latent risico. Mitigatie (later): zero-buffer detector + teardown/rebuild. Niet in scope; vermelden in changelog als known-unknown.
3. **Tap format kan != writer format zijn.** `kAudioTapPropertyFormat` kan ASBD's leveren met een andere sample rate of channel count dan onze writer-canonical (48 kHz / 2-ch Float32). De `RecorderAudioUtilities.convert` fallback dekt dit, maar conversie op de IO-thread is latency-gevoelig. Mitigatie: meten met `os_signpost` indien nodig; in de praktijk levert de tap voor system-output-clocked aggregates 48 kHz / 2 ch.
4. **`AVAudioPCMBuffer(pcmFormat:bufferListNoCopy:deallocator:)` levert een buffer die de raw `AudioBufferList`-data deelt.** De buffer mag niet langer leven dan de IO callback. Mitigatie: schrijven gebeurt synchroon vóór return; `writer.write(canonical)` kopieert intern via `AVAudioFile.write` (welke een diepe kopie maakt naar het file-format). Bevestigen tijdens implementatie dat geen referenties buiten de IOProc lekken.
5. **`AudioDeviceCreateIOProcIDWithBlock` queue-keuze.** De `ioQueue` moet hoog-prioritair zijn (`userInteractive`) om underruns te vermijden, en serieel (DispatchQueue default) zodat `writer.write` niet hoeft te locken voor write-volgorde. `ProcessTapAudioWriter` heeft al een `NSLock`; redundant maar veilig.
6. **`kAudioSubTapDriftCompensationKey` op `true`** kan kleine sample-rate-conversie introduceren wanneer system output op een ander tempo loopt dan 48 kHz. AudioCap gebruikt deze flag default; we volgen die keuze. Eventuele audible drift-artefacten zijn een follow-up.
7. **TCC prompt-tekst.** `NSMicrophoneUsageDescription` is al bijgewerkt naar *"Lorre transcribes audio locally — your microphone, system audio from other apps, or both."* (commit 7bd4cba). Geen wijziging nodig.
8. **Ad-hoc signing-effect was misdiagnose.** Branch-historie noteert dat Process Tap "silently zero-buffers in ad-hoc builds" was. Dat was deze bug. Na de fix: bevestigen op de huidige ad-hoc gesigneerde `/Applications/Lorre.app` dat system-only opname werkt. Indien nog steeds geen audio: opnieuw onderzoek; signing valt dan terug op tafel. Verwachting: niet nodig.

## Open vragen

Geen blokkerend. Implementatie kan starten zodra het plan-document is afgerond.

## Vervolgwerk (niet in deze spec)

- Listener op `kAudioHardwarePropertyDefaultSystemOutputDevice` + relink (risico #1).
- Zero-buffer detection + teardown/rebuild (risico #2).
- Per-app exclude / include picker (originele YAGNI uit eerdere spec).
- Migratie van het `claude/process-tap-system-audio` werk terug naar `master` zodra deze fix groen draait.
