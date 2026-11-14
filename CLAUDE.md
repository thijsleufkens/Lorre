# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Lorre is a macOS-only SwiftUI app for local transcription. Audio is captured (microphone, system audio via CoreAudio Process Tap, or both stems), processed locally via FluidAudio (Parakeet TDT 0.6B v3 for ASR; offline VBx for diarization), and exported as Markdown / plain text / JSON. Sessions persist to `~/Library/Application Support/Lorre/sessions/<uuid>/`.

Swift Package Manager: the `Lorre` executable and the `LorreCore` library. macOS 26+. No iOS/iPadOS targets and no plans for any.

## Toolchain — read first

`Package.swift` declares `// swift-tools-version: 6.3`. Use **Xcode's toolchain** (Swift 6.4.2 as of November 2026):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build
./scripts/swift_test.sh            # wrapper that selects Xcode's toolchain
```

Plain `swift build` resolves to the Command Line Tools, which open the package but cannot build the app: the SwiftUI macro plugins (`@State` etc.) are missing there.

With a toolchain older than 6.3 the package does not open at all. The workaround then is to lower line 1 of `Package.swift` to `6.2` for the duration of the command and revert it. **Never commit a tools-version change.**

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
| Install built app | `rm -rf /Applications/Lorre.app && ditto --noextattr --norsrc dist/Lorre.app /Applications/Lorre.app` (plain `cp -R` carries cloud-sync attributes along and breaks the signature) |
| Transcribe headless | `dist/Lorre.app/Contents/MacOS/Lorre transcribe <file> [--register]` |

All `swift` invocations need Xcode's toolchain as described above. `scripts/swift_test.sh` is a thin wrapper.

## Rebuild in progress — read before adding code

Lorre is being rebuilt around approved conversation records (spec: `docs/superpowers/specs/2026-11-13-lorre-product-spec.md`, plans in `docs/superpowers/plans/`). Two generations of code live side by side:

- **`Sources/LorreCore/`** (new): GUI-free library with the domain model (`Conversation`, `Participant`, `Segment`, `Outcome`, …), the SQLite store (GRDB; `LorreDatabase`, `ConversationStore`, `SearchStore`) and `LegacySessionImporter`. Rules: no UI imports, no dependency on the `Lorre` target, every model behind a protocol. Enum raw values are stored and exported, so renaming a case needs a migration (`DomainRawValueTests` guards this). Schema changes go in a new `DatabaseMigrator` migration in `Store/Schema.swift`, never by editing `v1`.
- **`Sources/LorreCapture/`** (new, with the moved Process Tap code): `LiveCaptureEngine` streams each track through `TimelineAudioWriter` straight into `conversations/<id>/` (`microphone.caf`, `system-audio.caf`); `RecordingCoordinator` creates the conversation row, folder and `recording.lock` at Start; `RecordingRecovery` turns abandoned recordings into `interrupted` conversations at launch. **Rule: nothing in this module deletes or rewrites a track**, except the empty files of a start that failed. `stop()` cannot throw. A microphone that delivers only digital silence (missing permission) is detected and reported.
- **`Sources/Lorre/`** (the app): the new screens, the bridge and the CLI. The old window is gone; what remains of the old generation is the speech core under `Core/` (used by the bridge and the CLI), `AppViewModel` for the old Settings tabs and the call prompt, and the old file store that the importer and `transcribe` read. The old `sessions/` folder is **read-only** for new code.

Recording goes through the menu-bar recorder (`Features/MenuBar/`: `RecorderModel`, `MenuBarRecorderView`, `AppServices`); the window's record button and the call prompt call into it. The old `AVFoundationRecorderService` is still compiled but no longer started from the UI. `Bridge/ConversationProcessor` runs the existing speech pipeline through a throwaway `FileSessionStore` and writes the transcript to the database plus `transcript.md`. `Bridge/ProcessingQueue` runs one conversation at a time.

The database is `~/Library/Application Support/Lorre/lorre.sqlite`. UUIDs are stored as uppercase text. Commands on the new store: `Lorre list [--json]`, `Lorre show <id>`, `Lorre process <id> [--no-export]`, `Lorre recover`, `Lorre import-legacy` (repeatable, never writes to `sessions/`); all take `--root <path>` for testing. A new subcommand must be added to `CLIRouting.subcommands` as well as `LorreCLI` (a test enforces it).

The main window is the new workspace (`Features/Workspace/`: Today, Conversations; `Features/Review/`: the review of one conversation; `Features/People/`: people and the brief for the next conversation; `Features/Onboarding/`: first run). Models are `@MainActor @Observable` classes that go through the LorreCore stores and reload (`WorkspaceModel`, `ReviewModel`, `PeopleModel`); views stay thin. Every visible text of these screens comes from `Features/App/Strings.swift` in Dutch and English (`StringsTests` checks both languages and bans technical words). Raw error texts never reach the screen: `ViewFormat.friendlyError` maps them.

Processing: with a microphone and a system track, `ConversationProcessor` transcribes each track separately (`Bridge/PerTrackTranscript.swift`): microphone segments belong to the user, the system track is diarized on its own. Anything else, or a per-track failure, takes the mix path. Afterwards `Bridge/ProposalRunner` asks the model named in the `proposalModel` setting for outcomes (`LorreCore/Proposal/`: `OutcomeProposer`, `TwoStepOutcomeProposer`, `OllamaTextGenerator`); empty setting means no proposals, which is the default because no tested model meets the thresholds (see `docs/superpowers/experiments/`). Measure a model with `Lorre eval` (`docs/eval.md`).

Agents read records through `Lorre records`, `Lorre record <id>`, `Lorre mark-processed`, or the MCP server `Lorre mcp` (`docs/agents.md`). People: `LorreCore/People/PeopleStore.swift`.

Work on this rebuild is split into packages with fixed contracts (`docs/superpowers/plans/2026-11-14-lorre-rebuild-m3-m7-packages.md`); screens must be checked in the running app after merging, since tests do not see layout.

Signing: `LORRE_SIGN_IDENTITY` selects the code-signing identity for `scripts/package_macos_app.sh` (default ad-hoc). See `docs/signing.md`.

Automatic updates (Sparkle, `Features/Updates/`, `scripts/make_release.sh`; the package script embeds `Sparkle.framework`, signs it first, and writes the feed keys only when `LORRE_UPDATE_FEED_URL` and `LORRE_UPDATE_PUBLIC_KEY` are set): see `docs/updates.md`.

## Repository layout

- `Sources/Lorre/App/` — `LorreEntry.swift` is the `@main` entrypoint: it routes via `CLIRouting` to either the headless CLI or the SwiftUI app. `LorreApp.swift` is the SwiftUI scene root: a `WindowGroup` with `WorkspaceView`, a `Settings` scene and the menu-bar extra. It owns `AppServices` (database, recorder, processing queue, workspace model) and the `AppViewModel` `@StateObject` that the Settings tabs and the call watcher still use.
- `Sources/Lorre/CLI/` — the dual-mode CLI (swift-argument-parser): `CLIRouting` (argv → CLI vs GUI), `LorreCLI` root, `TranscribeCommand` (the `transcribe` subcommand), `TranscribeServiceFactory` (headless FluidAudio wiring), `TranscribeOutputPlan` (pure output-target resolution). The CLI reuses the GUI-free core (`ProcessingCoordinator`, `FileSessionStore`, `MarkdownExportService`, `AutomaticExporter`).
- `Sources/Lorre/Core/Domain/` — value types and protocols: `Models.swift` holds `SessionManifest`, `TranscriptDocument`, `AppSettings`, `SpeakerProfile`, etc. All `Codable + Equatable + Sendable`, all schema-versioned with optional-field fallback decoding.
- `Sources/Lorre/Core/Persistence/` — `FileSessionStore`, `KnownSpeakerStore`, `AtomicFileWriter`. Sessions live one folder per UUID with `session.json`, `transcript.json`, and audio stems alongside.
- `Sources/Lorre/Core/Processing/` — orchestration of recording → diarization → ASR → speaker labeling. `ProcessingCoordinator` is the hub; FluidAudio adapters live next to it.
- `Sources/Lorre/Core/Support/` — service-layer infrastructure: `AVFoundationRecorderService` (mic via AVCaptureDevice), `ProcessTapSystemAudioCapture` (system audio via CoreAudio Process Tap), `AppSettingsStore`, runtime capability detection, audio utilities.
- `Sources/Lorre/Core/Export/` — Markdown / plain text / JSON export.
- `Sources/Lorre/Core/DesignSystem/` — the Sage design tokens (`DesignSystem.swift`) and `SpeakerBadgeView`. Colors use `Color.dynamic(light:dark:)` for live appearance switching via `NSColor` providers.
- `Sources/Lorre/Features/Shell/` — `AppViewModel` and its support types. No view of the old window is left: the view model remains for the Settings tabs (flat `@Published` properties, bound to `viewModel.isXxx` getters and `viewModel.setXxx(_:)` setters), the call watcher and call prompt (which start recordings through `externalRecorderStart`), global dictation, and the old record-and-process path. A few members are kept although no view reaches them (audio import, global dictation actions, the call prompt actions, `stopRecordingTapped`/`launchProcessing`, `setRecordingSource`) because removing them is a product decision, and some tests still use them.
- `Sources/Lorre/Features/MenuBar/` — the menu-bar recorder: `RecorderModel`, `MenuBarRecorderView`, `AppServices`. Its texts and notifications come from `Strings` in Dutch and English.
- `Sources/Lorre/Features/Settings/` — the `Settings` scene's tabs (General / Speech & Models / Speakers / Records / About). Most are a SwiftUI `Form` bound to `AppViewModel`; the records tab uses the database-backed `SettingsStore`.
- `Sources/Lorre/Features/Workspace/`, `Review/`, `People/`, `Onboarding/`, `App/Strings.swift` — the new main window and its screens, described under "Rebuild in progress". `Sources/Lorre/Bridge/` connects recordings to the old speech pipeline; `Sources/Lorre/MCP/` is the agent server.
- `Tests/LorreTests/` — XCTest for the app target (models, bridge, CLI, strings, schema migrations of the old store, the old core); `LorreCoreTests` and `LorreCaptureTests` cover the libraries. SwiftUI layout is not unit-tested: verify screens in the running app.

## Architecture in one breath

The main window is `WorkspaceView` on `WorkspaceModel`/`ReviewModel`/`PeopleModel` (LorreCore stores). Recording is `RecorderModel` (menu bar) on `LorreCapture`; finished recordings go through `ProcessingQueue` → `ConversationProcessor` (old speech pipeline, `ProcessingCoordinator` + FluidAudio) into the database. `AppViewModel` (MainActor

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
