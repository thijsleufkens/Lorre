# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Lorre is a macOS-only SwiftUI app for local transcription. Audio is captured (microphone, system audio via CoreAudio Process Tap, or both stems), processed locally via FluidAudio (Parakeet TDT 0.6B v3 for ASR; offline VBx for diarization), and exported as Markdown / plain text / JSON. Sessions persist to `~/Library/Application Support/Lorre/sessions/<uuid>/`.

Single executable target, Swift Package Manager. macOS 15+. No iOS/iPadOS targets and no plans for any.

## Toolchain quirk — read first

`Package.swift` declares `// swift-tools-version: 6.3`. The Xcode that ships locally on this machine has Swift 6.2.4 (from Xcode 26.x). Plain `swift build` / `swift test` will fail with a tools-version mismatch.

Two workarounds, pick one per command:

1. Route through Xcode's toolchain explicitly:
   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
   ```
2. Temporarily lower line 1 of `Package.swift` to `// swift-tools-version: 6.2`, run the command, **revert before committing**. The package features in use (`resources: [.copy("Fixtures")]`, etc.) are 6.2-compatible. Never commit a tools-version change.

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

All `swift` invocations need the toolchain workaround above. `scripts/swift_test.sh` is a thin wrapper.

## Repository layout

- `Sources/Lorre/App/` — `LorreApp.swift`, the `@main` SwiftUI scene root. Owns the `AppViewModel` `@StateObject` and exposes both a `WindowGroup` and a `Settings` scene.
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
4. At least one process in the tap's include list must be actively producing audio at the moment the tap is created — otherwise the IOProc fires but every buffer is silent. In system-only mode Lorre satisfies this by running an `AudioOutputWarmer` (a silent `AVAudioEngine` output at volume 0) for the duration of the recording. In mic+system mode the warmer is skipped — the mic `AVAudioEngine` already keeps the audio subsystem warm, and a second engine on the same device introduces a monitoring path. The mic engine also enables `setVoiceProcessingEnabled(true)` in mic+system mode for AEC + noise suppression of whatever any AEC-aware app (Teams, Zoom, FaceTime, Discord) routes through the shared output.

**Known limitation**: built-in MacBook speakers + built-in mic + an audio source that does **not** enable system VP (Safari, Chrome, Music app, etc.) → acoustic feedback from speakers to mic produces an echo in the mixed audio file. Transcription quality is unaffected for the goal of these meetings. Workarounds: use headphones/AirPods, or use an external mic. The realistic meeting case (Teams/Zoom/FaceTime active) does enable system-wide VP and is unaffected.

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
