# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Lorre is a macOS-only SwiftUI app for local transcription. Audio is captured (microphone, system audio via CoreAudio Process Tap, or both stems), processed locally via FluidAudio (Parakeet TDT 0.6B v3 for ASR; offline VBx for diarization), and exported as Markdown / plain text / JSON. Sessions persist to `~/Library/Application Support/Lorre/sessions/<uuid>/`.

Single executable target, Swift Package Manager. macOS 15+. No iOS/iPadOS targets and no plans for any.

## Toolchain quirk — read first

`Package.swift` declares `// swift-tools-version: 6.3`. No Swift 6.3 toolchain is installed on this machine — only Swift 6.1.2 (CommandLineTools) and 6.2.4 (Xcode 26.x). Plain `swift build` / `swift test` will fail with a tools-version mismatch.

**The only working workaround:** temporarily lower line 1 of `Package.swift` to `// swift-tools-version: 6.2`, run the command, **revert before committing**. The package features in use (`resources: [.copy("Fixtures")]`, etc.) are 6.2-compatible. Never commit a tools-version change. E.g.:

```bash
cp Package.swift /tmp/pkg.bak && sed -i '' '1s/6.3/6.2/' Package.swift
./scripts/swift_test.sh            # or: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build
cp /tmp/pkg.bak Package.swift       # revert; verify `head -1 Package.swift` shows 6.3 and `git status` is clean
```

(The old "route through Xcode's toolchain with `DEVELOPER_DIR` + `xcrun`" trick no longer suffices on its own: Xcode's 6.2.4 still can't open a 6.3 package. You must lower the tools-version regardless.)

The `scripts/package_macos_app.sh` script must also be run with `DEVELOPER_DIR` set and `PATH` including Xcode's toolchain:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH \
./scripts/package_macos_app.sh release
```

## Common commands

| Task | Command |
|---|---|
| Build | `swift build` |
| Run app | `swift run` |
| Test all | `swift test` |
| Test one | `swift test --filter <TestClassName>` or `swift test --filter <TestClassName>.<methodName>` |
| Package `.app` | `./scripts/package_macos_app.sh release` → `dist/Lorre.app` |
| CI parity | `./scripts/ci_check.sh` |
| Install built app | `rm -rf /Applications/Lorre.app && cp -R dist/Lorre.app /Applications/` |
| Transcribe headless | `dist/Lorre.app/Contents/MacOS/Lorre transcribe <file> [--register]` |

All `swift` invocations need the toolchain workaround above. `scripts/swift_test.sh` is a thin wrapper.

## Repository layout

- `Sources/Lorre/App/` — `LorreEntry.swift` is the `@main` entrypoint: it routes via `CLIRouting` to either the headless CLI or the SwiftUI app. `LorreApp.swift` is the SwiftUI scene root (no longer `@main`); it owns the `AppViewModel` `@StateObject` and exposes both a `WindowGroup` and a `Settings` scene.
- `Sources/Lorre/CLI/` — the dual-mode CLI (swift-argument-parser): `CLIRouting` (argv → CLI vs GUI), `LorreCLI` root, `TranscribeCommand` (the `transcribe` subcommand), `TranscribeServiceFactory` (headless FluidAudio wiring), `TranscribeOutputPlan` (pure output-target resolution). The CLI reuses the GUI-free core (`ProcessingCoordinator`, `FileSessionStore`, `MarkdownExportService`, `AutomaticExporter`).
- `Sources/Lorre/Core/Domain/` — value types and protocols: `Models.swift` holds `SessionManifest`, `TranscriptDocument`, `AppSettings`, `SpeakerProfile`, etc. All `Codable + Equatable + Sendable`, all schema-versioned with optional-field fallback decoding.
- `Sources/Lorre/Core/Persistence/` — `FileSessionStore`, `KnownSpeakerStore`, `AtomicFileWriter`. Sessions live one folder per UUID with `session.json`, `transcript.json`, and audio stems alongside.
- `Sources/Lorre/Core/Processing/` — orchestration of recording → diarization → ASR → speaker labeling. `ProcessingCoordinator` is the hub; FluidAudio adapters live next to it.
- `Sources/Lorre/Core/Support/` — service-layer infrastructure: `AVFoundationRecorderService` (mic via AVCaptureDevice), `ProcessTapSystemAudioCapture` (system audio via CoreAudio Process Tap), `AppSettingsStore`, runtime capability detection, audio utilities.
- `Sources/Lorre/Core/Export/` — Markdown / plain text / JSON export.
- `Sources/Lorre/Core/DesignSystem/` — the Sage design tokens (`DesignSystem.swift`) and small shared components (`CapsLabel`, `SearchFieldView`, `SpeakerBadgeView`, `IndexRailView`, `LorreWordmark`, `SessionDateGrouping`, `SessionDateGroupHeader`). Colors use `Color.dynamic(light:dark:)` for live appearance switching via `NSColor` providers.
- `Sources/Lorre/Features/Shell/` — `AppShellView`, `AppViewModel`, the session sidebar (`SessionShelfSidebarView`). `AppViewModel` is the single source of truth — properties are **flat `@Published`** on the view model (NOT nested under an `appSettings` namespace). Settings bind directly to `viewModel.isXxx` getters and `viewModel.setXxx(_:)` setters.
- `Sources/Lorre/Features/Recorder/` — `RecorderStageViews.swift` is the recorder pre/active/processing UI in one file. The pre-recording pane is the minimal hero ("— Recorder" kicker + title + `.borderedProminent` Start button + 2-line status). The active-recording panel and processing pipeline live here too.
- `Sources/Lorre/Features/Settings/` — the `Settings` scene's four tabs (General / Speech & Models / Speakers / About). Each tab is a SwiftUI `Form` bound to `AppViewModel`.
- `Sources/Lorre/Features/Transcript/` — transcript playback, segment rows, speaker reassignment, export controls.
- `Tests/LorreTests/` — XCTest. 54 tests as of this writing. The only behavioral logic that is TDD-tested is `SessionDateGrouper` (5 tests) and the schema migration paths (5 fixture-driven tests). Audio capture, view models, and SwiftUI views are not directly unit-tested; verify those manually with a real recording.

## Architecture in one breath

`AppViewModel` (MainActor `@MainActor` `ObservableObject`) owns app state. UI binds to its flat `@Published` properties and invokes its methods. Persistence and audio capture are services injected via `AppDependencies` (see `live()` factory). Captured audio flows: `AVFoundationRecorderService` → `ProcessingCoordinator` → FluidAudio → `TranscriptDocument` written to disk → reloaded by the view model.

System audio uses macOS 15's CoreAudio Process Tap (`ProcessTapSystemAudioCapture`). The aggregate device anchors to the default system output device as `MainSubDevice` for clock, lists every non-self process via `stereoMixdownOfProcesses`, and reads PCM through `AudioDeviceCreateIOProcIDWithBlock` (matches the [insidegui/AudioCap](https://github.com/insidegui/AudioCap) reference pattern). Four things were essential to get this working on ad-hoc signed builds:

1. Aggregate device must include `kAudioAggregateDeviceMainSubDeviceKey` (real hardware clock).
2. Tap I/O must use `AudioDeviceCreateIOProcIDWithBlock` directly, not `AVAudioEngine + installTap`.
3. The `.app` bundle must be code-signed with `com.apple.security.device.audio-input` entitlement, and Info.plist must contain `NSAudioCaptureUsageDescription`. Without either, the tap creates successfully and the IOProc fires, but all delivered buffers are silent.
4. Tap delivery is **event-driven**: the IOProc only fires while a process in the include list is actually producing audio. A tap created during silence delivers nothing until a *listed* process starts producing; the include list is a snapshot of CoreAudio's client processes at creation time (Chrome with an open-but-paused stream is in it; a process that opens its first audio stream after recording start is not — known limitation). In system-only mode an `AudioOutputWarmer` (silent `AVAudioEngine` output at volume 0) runs for the duration of the recording. Because delivery has gaps, `ProcessTapAudioWriter` is timeline-aware: it anchors t=0 to the recording start (mic capture start in mic+system mode) and pads delivery gaps >0.35 s with silence so the stems stay wall-clock aligned — never mix stems at sample 0 without this.

In mic+system mode the mic engine enables `setVoiceProcessingEnabled(true)` for AEC + noise suppression. **Voice processing changes three things at once**, each of which broke this mode before (May–June 2026 bug hunt):

- **Other-audio ducking**: VP ducks every non-VP source (Chrome, Music) system-wide; the default level effectively mutes them. Fixed with `inputNode.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)` right after enabling VP. Even `.min` still attenuates other audio ~7 dB (macOS behavior). VP-aware apps (Teams/Zoom/FaceTime) are never ducked.
- **Extra aggregate input stream**: with VP active, the anchored output device exposes an additional input stream (the AEC reference), so the IOProc's ABL carries *two* interleaved streams and the whole-ABL `AVAudioPCMBuffer(bufferListNoCopy:)` wrap returns nil on every callback (→ empty stem). The IOProc falls back to wrapping just the *last* stream (sub-device streams precede sub-tap streams).
- **5-channel mic format**: VP reports the built-in mic as a 48 kHz **5-channel** input (identical channels), and `AVAudioConverter` silently produces all-zero output when downmixing >2 channels to mono. Capture reduces >2ch input to mono channel 0 (`lorre_monoChannelZero`), and the mix path's `ChunkedSampleReader` does the same defensively for stems on disk.

Two further AVFoundation traps now handled in `RecorderAudioUtilities`: `AVAudioFile.read(into:)` may return fewer frames than requested even mid-file (loop until done), and a one-shot `AVAudioConverter.convert` call without an end-of-stream drain truncates the tail of resampled audio.

Mic-only mode deliberately records the raw microphone without VP — it captures whatever the room (including the speakers) sounds like, as any voice-memo app does.

See `docs/superpowers/specs/2026-05-14-process-tap-clock-fix.md` and `scripts/package_macos_app.sh` for the full setup.

## Persistence + schema migration

`SessionManifest`, `TranscriptDocument`, and `AppSettings` each carry a `schemaVersion` and use custom `Codable` conformance with `decodeIfPresent ... ?? default` to read older shapes from disk. When adding a non-additive change to any of these types, bump its `currentSchemaVersion`, add a fixture under `Tests/LorreTests/Fixtures/`, and add a migration test in `SchemaMigrationTests.swift`.

## Design system

Sage palette (bone canvas / forest dark / moss accent / clay live state) with italic-serif "Lorre" voice via Iowan Old Style. All color tokens are dynamic light/dark via the `Color.dynamic(light:dark:)` helper. Buttons go through `PrimaryControlButtonStyle` / `SecondaryControlButtonStyle` (pill-shaped capsules). Panels use `.dsPanelSurface()`; shadows use `.dsSurfaceShadow()` and `.dsPanelShadow()`.

**Rule:** never hardcode hex colors, font sizes, or radii outside `DesignSystem.swift`. If a token doesn't exist for what you need, add one rather than inlining a value.

## Spec / plan / implement workflow

`docs/superpowers/specs/` holds design documents (one per sub-project), `docs/superpowers/plans/` holds task-by-task implementation plans. The convention is: brainstorm → spec → plan → execute via subagent-driven development → PR → merge. Existing spec/plan pairs in those folders show the shape (the Studio Sage design refresh and the Apple-native Recorder restructure are good references).

## Building releases / TCC quirk

`scripts/package_macos_app.sh release` produces an ad-hoc-signed `.app` with `com.apple.security.device.audio-input` entitlement applied at codesign time. **Every rebuild changes the binary hash and resets macOS TCC permissions for the bundle.** Expect to re-grant microphone and audio-capture permissions after each install. This is not a bug; it's the cost of ad-hoc signing.

To clear a stuck TCC state during development:
```bash
tccutil reset All com.jessescholtes.lorre
```

The bundle identifier `com.jessescholtes.lorre` is inherited from upstream (jjscholtes/Lorre); changing it would also reset TCC.

## Privacy and local data (from README)

Lorre stores everything under `~/Library/Application Support/Lorre/`. Each session is one folder containing `session.json`, `transcript.json`, optional `audio.caf` / `microphone.caf` / `system-audio.caf` stems, and exports. With Privacy Mode on, source audio is deleted after transcription completes; the transcript stays.
