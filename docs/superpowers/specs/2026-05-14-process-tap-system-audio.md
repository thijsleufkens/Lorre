# System audio via CoreAudio Process Tap (drop ScreenCaptureKit)

**Status:** brainstormed, awaiting implementation plan
**Date:** 2026-05-14
**Branch:** `claude/process-tap-system-audio`
**Sub-project:** D of four (A merged: Recorder + Settings restructure. B = sidebar native chrome — pending. C = remaining pane polish — pending.)

## Doel

Vervang Lorre's system-audio capture-mechanisme van **ScreenCaptureKit** (`SCStream` + `SCContentSharingPicker`) door macOS 15 / CoreAudio's **Process Tap API** (`CATapDescription` + `AudioHardwareCreateProcessTap`). Twee user-facing voordelen:

1. **Screen Recording permission verdwijnt** uit Lorre's TCC-dependencies. Lorre vraagt geen schermopname-rechten meer, omdat de Process Tap-API binnen de audio-permissieklasse leeft, niet de schermopname-klasse.
2. **De `SCContentSharingPicker`-dialog verdwijnt per opname.** De huidige flow toont elke keer dat je System audio (of Mic + System) start een Apple-systeem-dialog met "wat wil je delen". Met Process Tap is dat éénmalige permission-grant, daarna stille captures.

Bijkomend voordeel: minder code-oppervlak. ScreenCaptureKit-pad in `AVFoundationRecorderService.swift` (36 referenties) gaat in zijn geheel weg.

Geen UI-veranderingen, geen gedragsveranderingen voor de gebruiker behalve de eerste permissie-prompt (één keer) en het wegvallen van de elke-keer-picker (per opname). De source-segmented control in de toolbar blijft `Mic / Mic + System / System`. Captured audio bestanden, stems, mixing — alles blijft hetzelfde formaat.

## Scope

**In scope**
- Bump `Package.swift` minimum macOS target van `.v14` naar `.v15` (Sequoia, sept 2024).
- Nieuw bestand `Sources/Lorre/Core/Support/ProcessTapSystemAudioCapture.swift` met de Process-Tap-implementatie.
- Vervang in `Sources/Lorre/Core/Support/AVFoundationRecorderService.swift` de `startSystemAudioCapture` implementatie en de `pickSystemAudioFilter` helpers door calls naar de nieuwe Process-Tap-module.
- Verwijder alle `#if canImport(ScreenCaptureKit)` / `import ScreenCaptureKit` / `SCStream` / `SCContentFilter` / `SCContentSharingPicker` / `ScreenCapturePickerObserverBox` code uit `AVFoundationRecorderService.swift`.
- Process Tap scope: **alle running processen behalve Lorre's eigen PID**, mono mixdown. Geen UI-picker.
- Permission preflight: detecteer `notDetermined` vs `denied` voor de nieuwe audio-tap TCC-klasse, en open System Settings → Privacy & Security → "Audio Recording" (of de juiste pane) bij denial — analoog aan de bestaande microfoon-preflight.
- Bijwerken van eventuele Info.plist (`NSAudioCaptureUsageDescription` als macOS dat verlangt — wordt in implementatie vastgesteld).

**Out of scope**
- UI-veranderingen aan de source-segmented control, Settings, of waar dan ook. De toolbar blijft `Mic / Mic + System / System`.
- Migratie van bestaande sessions/audio — formaat blijft `.caf` met dezelfde sample rate.
- Per-app process picker (een UI om één specifieke app te kiezen). YAGNI: "alle apps behalve Lorre" matcht het bestaande default-gedrag van de SCContentSharingPicker "All audio".
- Microphone recording — onveranderd, blijft `AVCaptureDevice`.
- Import-audio flow — onveranderd.
- Live preview / streaming transcription — werkt verder gewoon zodra de Process Tap PCM-buffers levert (identiek interface).
- Sub-project B (sidebar native chrome) en C (Processing/Transcript polish) — apart.

## Achtergrond — Process Tap API kort

(macOS 14.4+, Apple's `CoreAudio` / `AudioToolbox`):

```swift
import CoreAudio
import AudioToolbox

// 1. Beschrijf wat we willen tappen.
let lorrePID = getpid()
let description = CATapDescription(stereoMixdownOfProcesses: nil)
description.processes = []                     // empty = all processes
description.muteBehavior = .unmuted             // we want to hear the audio
description.isPrivate = false                   // visible in audio mixers (irrelevant for us)
description.exceptProcesses = [lorrePID]        // exclude ourselves

// 2. Create the tap. Returns an AudioObjectID we can read like any input device.
var tapID = AudioObjectID(kAudioObjectUnknown)
AudioHardwareCreateProcessTap(description, &tapID)

// 3. Aggregate device that bundles the tap as an input.
// Use AudioHardwareCreateAggregateDevice with the tap UID, then read via AVAudioEngine.

// 4. AVAudioEngine setup is then identical to mic capture.

// 5. Destroy on stop: AudioHardwareDestroyProcessTap(tapID)
```

(De exacte API-namen kunnen iets afwijken — wordt in de implementatieplan-fase preciezer gemaakt. Het CATapDescription-object werd in 14.4 geïntroduceerd, plus de bijbehorende `AudioHardwareCreate*`-functies.)

## Component-architectuur

### `ProcessTapSystemAudioCapture.swift` (nieuw)

Klasse die de hele Process-Tap-lifecycle wraps. Public interface:

```swift
actor ProcessTapSystemAudioCapture {
    /// Start tappen van alle audio behalve onze eigen PID, schrijven naar `outputURL` als .caf.
    /// Returnt zodra de tap actief is en de eerste buffer geschreven is.
    func start(outputURL: URL) async throws -> Started

    /// Stop tappen, sluit het bestand. Returnt de actuele duur in seconden.
    func stop() async throws -> Stopped

    /// Optional live PCM stream voor live transcription preview.
    /// Returnt een AsyncStream<AVAudioPCMBuffer> zolang de tap actief is.
    nonisolated func makeLiveBufferStream() -> AsyncStream<AVAudioPCMBuffer>

    struct Started: Sendable { let startedAt: Date }
    struct Stopped: Sendable { let endedAt: Date; let durationSeconds: Double }
}
```

Dezelfde shape als het huidige `startSystemAudioCapture` resultaat — alleen de interne implementation verschuift van SCStream-callbacks naar AVAudioEngine met een tap-device als input.

### `AVFoundationRecorderService.swift` (gewijzigd)

- Verwijder `#if canImport(ScreenCaptureKit)` blokken, `import ScreenCaptureKit`, `pickSystemAudioFilter()`, `startSystemAudioCapture(...)` (oude variant), `ScreenCapturePickerObserverBox`.
- Vervang met:
  ```swift
  if request.source.includesSystemAudio {
      let processTap = ProcessTapSystemAudioCapture()
      systemAudioCapture = processTap
      systemStart = try await processTap.start(outputURL: systemAudioTempURL)
  }
  ```
- Mixing van mic + system audio stems (`combineStereoOrMonoStems`) blijft ongewijzigd — de twee `.caf` files hebben dezelfde structuur als nu.

### Info.plist / entitlements

- `NSMicrophoneUsageDescription` — blijft (microphone capture). Tekst eventueel aanscherpen.
- `NSAudioCaptureUsageDescription` (of de exacte macOS-15 sleutel, te verifiëren) — **toevoegen** voor de tap-permissieprompt. Tekst bv. "Lorre captures audio from other apps so that meetings and system audio can be transcribed locally." Wordt eenmalig getoond bij de eerste system-audio opname.
- Entitlement `com.apple.security.device.audio-input` — blijft (vereist door zowel mic als tap).
- Mogelijk extra entitlement voor process-tap (bv. een gerelateerde audio-extension). Wordt vastgesteld bij implementatie; spec verwacht **geen** nieuwe code-sign of provisioning-werk omdat Lorre nu ad-hoc gesigneerd is, niet via een developer ID.

### Permission preflight

Pattern volgt de bestaande microfoon-flow:
1. Op `Start recording`: als source system audio bevat, check de tap-permissiestatus.
2. `.notDetermined` → trigger de native prompt via een lichte init-and-discard call (of via `AudioHardwareCreateProcessTap` zelf — dat triggert de prompt).
3. `.denied` → toon een banner of redirect naar System Settings → Privacy → Audio Recording met dezelfde `openSystemSettings(for:)`-helper als nu voor de mic.
4. `.authorized` → start de tap stilletjes.

## Acceptance criteria

- [ ] `Package.swift` heeft `platforms: [.macOS(.v15)]`.
- [ ] `Sources/Lorre/Core/Support/ProcessTapSystemAudioCapture.swift` bestaat met de public interface hierboven.
- [ ] Geen `#if canImport(ScreenCaptureKit)`, `import ScreenCaptureKit`, `SCStream*`, `SCContentFilter*`, `SCContentSharingPicker*`, of `ScreenCapturePickerObserverBox` ergens in `Sources/`.
- [ ] Een sessie opnemen met source = **Microphone**: geen audio-recording TCC-prompt, geen pickers (alleen mic-prompt eerste keer — gedrag onveranderd).
- [ ] Een sessie opnemen met source = **System audio**: bij eerste keer één macOS-prompt voor audio-recording. Geen `SCContentSharingPicker`-dialog meer. Geen Screen Recording prompt meer.
- [ ] Een sessie opnemen met source = **Mic + System**: bij eerste keer beide TCC-prompts (mic + audio recording). Geen picker.
- [ ] `/Applications/Lorre.app` toont **geen** entry meer onder System Settings → Privacy & Security → Screen Recording (na verwijderen + reinstall + permission grant).
- [ ] Captured audio files (.caf) hebben dezelfde sample-rate, channels, en formaat als vóór de migratie (geen breaking change voor opgeslagen sessies).
- [ ] Live preview / streaming transcription werkt nog steeds tijdens system-audio opname.
- [ ] Mic stems en system-audio stems worden nog steeds als losse files opgeslagen en correct gemixt naar de gecombineerde stream voor Mic + System mode.
- [ ] Bestaande 54 tests blijven groen.
- [ ] Permission-denied flow toont een leesbare error en linkt naar System Settings.

## Risico's

1. **Process Tap API-details kunnen afwijken.** Apple's documentatie is mager. Tijdens implementatie kan blijken dat de exacte API-naam, parameter-volgorde, of permission-flow anders is dan hier beschreven. De spec accepteert dat het plan een verkennings-fase nodig heeft.
2. **Aggregate device vs. tap-input via AVAudioEngine.** Sommige Apple-voorbeelden tonen dat je een Process Tap moet wrappen in een `AudioAggregateDevice` om het via `AVAudioEngine` of `AVAudioInputNode` te kunnen lezen. Andere docs suggereren dat je rechtstreeks `AudioObjectAddPropertyListener` op de tap kunt zetten. De implementatie zal hier een keuze maken (aggregate device is veiliger en bekender).
3. **Audio-recording permission-prompt tekst.** macOS toont een vooraf-gedefinieerd prompt-text met de `NSAudioCaptureUsageDescription` value als sub-tekst. Goede prompt-tekst opstellen om gebruikersweerstand te minimaliseren.
4. **Self-exclusion via `exceptProcesses`.** Lorre's eigen PID moet ge-excludeerd worden om audio-feedback-loops te voorkomen. Werkt alleen voor het eigen proces — als Lorre child-processes spawn-t (b.v. FluidAudio helpers), zouden die ook moeten worden ge-excludeerd. Snel verifiëren bij implementatie.
5. **macOS 15.0 vs 15.x.** Sommige API-fixes voor Process Tap zijn pas in macOS 15.1 of 15.2 geland. Als blijkt dat 15.0 niet werkt, bump naar de eerste werkende minor (waarschijnlijk niet erger dan 15.1).
6. **De Process Tap "captures" ook lokale playback van bv. een YouTube tab.** Dat is gewenst gedrag (we willen alle system audio) maar betekent dat als de gebruiker tegelijk Spotify aan heeft, dat ook in de opname zit. Documenteer als "by design" in changelog.
7. **Lorre toont nu geen "Screen Recording" pop-up meer maar de eerste keer wel een audio-prompt.** Bestaande gebruikers die al gewend zijn aan de oude flow zien een ander prompt. Verwijs in release-notes naar de change.
8. **Bestaande Screen Recording permission grant blijft achter** in System Settings → Privacy & Security → Screen Recording na de upgrade, ook al gebruikt Lorre het niet meer. Documenteer als "kan handmatig verwijderd worden — niet vereist".

## Open vragen

Geen blokkerend. De API-details (exacte function names, permission key, aggregate-device boilerplate) worden in het implementatieplan ingevuld na een korte verkennings-pass.
