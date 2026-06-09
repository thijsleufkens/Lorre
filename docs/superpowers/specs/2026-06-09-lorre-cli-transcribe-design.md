# Lorre CLI: headless `transcribe` subcommand

**Date:** 2026-06-09
**Status:** Design approved, pending implementation plan

## Goal

Give Lorre a headless command-line entrypoint so an audio **or video** file can be
transcribed without driving the GUI. Two outcomes from one command:

1. **Headless transcript** — emit the transcript (Markdown/JSON) to a file or stdout,
   without leaving anything in the Lorre library.
2. **Registered session** (`--register`) — additionally persist the file as a normal
   Lorre session (visible in the GUI library) and write the auto-export envelope
   (Markdown + JSON) to the configured export folder, so the existing
   `strongbad-lorre-ingest` → Postgram → LinkedIn pipeline picks it up
   (dedup on `session.id`).

This also makes Lorre scriptable/automatable (e.g. by an agent) via:

```
/Applications/Lorre.app/Contents/MacOS/Lorre transcribe "<file>" --register
```

## Background / current state

- Single SPM executable target `Lorre` (`Package.swift`), `@main` in
  `Sources/Lorre/App/LorreApp.swift`. Dependency: `FluidAudio` (Parakeet TDT 0.6B v3,
  CoreML on the Neural Engine).
- The transcription core is **GUI-free**: `Core/Processing` (`ProcessingCoordinator`),
  `Core/Persistence` (`FileSessionStore`), `Core/Export` (`MarkdownExportService`,
  `AutomaticExportFileNameBuilder`), `Core/Domain` (`Models`) import no SwiftUI/AppKit.
  Only `Core/DesignSystem` and three `Core/Support` files (`AVFoundationRecorderService`,
  `CallWatcherPlatformServices`, `GlobalDictationPlatformServices`) are GUI-coupled.
- Pipeline contract:
  - `FileSessionStore.createSession(NewSessionDraft) -> SessionManifest` creates the
    session directory + manifest; the audio file must live at
    `sessionDirectoryURL(for:)/audioFileName`.
  - `ProcessingCoordinator.process(sessionId:enableDiarization:diarizationExpectedSpeakers:`
    `exportDiarizationDebugArtifact:deleteAudioAfterTranscription:languageCode:onProgress:)`
    `async throws -> TranscriptDocument` loads the session, ensures models, transcribes
    `sessionDir/audioFileName`, diarizes, assembles, saves the transcript, sets status
    `.ready`, and returns the `TranscriptDocument`.
  - Auto-export config `AutomaticMarkdownExportConfiguration` (folder path + filename
    template `{date}-{smart_title}.md`) lives in the `settings` dependency. The actual
    md+json envelope write currently sits in `AppViewModel` (~lines 2560–2590) using
    `AutomaticExportFileNameBuilder.fileName(...)` + `MarkdownExportService.renderJSON(...)`.
- The GUI import (`SessionShelfSidebarView` "Import Audio" → `fileImporter` with
  `allowedContentTypes: [.audio]` → `AppViewModel.importAudioFile(at:)`) copies the
  source audio into a new session dir and runs the same pipeline. The `.audio` filter is
  why a `.mp4` cannot be selected in the picker today.

## Chosen approach: dual-mode entrypoint (approach A)

Keep everything in the existing `Lorre` target. The shipping app-bundle binary
(`Lorre.app/Contents/MacOS/Lorre`) gains a CLI mode. Because the CLI runs inside the
exact same signed bundle as the GUI, FluidAudio model cache / CoreML / ANE behave
identically to the GUI app — this is the lowest-risk path and is what lets an agent
drive transcription from the command line.

Rejected alternatives:
- **B — split into `LorreCore` library + `Lorre` GUI + `lorre` CLI binary.** Cleaner
  long-term, but a larger refactor and it re-introduces the risk "does FluidAudio run
  outside the app bundle / without code signing?". Can be revisited later.
- **C — `lorre://` URL scheme + `.onOpenURL`.** Still launches the GUI, no headless
  transcript, couples to app state. Does not satisfy the "both" requirement.

## Components

### 1. Entrypoint (dual-mode)

- Remove `@main` from `LorreApp`.
- Add `LorreEntry` with a custom `static func main()` that inspects
  `CommandLine.arguments`:
  - first argument is a known subcommand (`transcribe`) → run the CLI
    (`AsyncParsableCommand`) and exit; SwiftUI / `NSApplication` never starts.
  - otherwise → `LorreApp.main()` (current GUI behaviour, unchanged).
- New package dependency: `swift-argument-parser`.

### 2. CLI surface

```
Lorre transcribe <input> [-o|--out <path>] [--format md|json|both]
                         [--register] [--language <code>]
                         [--no-diarization] [--speakers <n>] [--quiet]
```

- `<input>`: path to an audio **or** video file.
- `--out`/`-o`: destination path; omitted → transcript to stdout.
- `--format`: `md` (default) or `json` → written to `--out` (or stdout). `both` requires
  `--out`, which is treated as a path stem: writes `<stem>.md` and `<stem>.json`.
- `--register`: persist as a real session + write the auto-export envelope (see §4/§5).
- `--language`: ASR language code; omitted → automatic detection.
- `--no-diarization`: disable speaker diarization.
- `--speakers <n>`: expected-speaker-count hint (maps to `DiarizationSpeakerCountHint`).
- `--quiet`: suppress progress output (progress otherwise to stderr).
- Exit code `0` on success, non-zero on failure (message to stderr).

### 3. Input decoding — audio + video (`MediaAudioImporter`)

New GUI-free helper in `Core` that, given any file URL, produces the audio file the
pipeline expects (same target format/normalization as the current GUI import path):

- Use AVFoundation (`AVURLAsset` / `AVAssetReader`) to read the first audio track and
  write a normalized audio file into the destination session directory.
- AVAsset transparently handles `mp4`/`mov`/`m4a`/`wav`/`mp3`/etc., so a video file's
  audio track is extracted directly — eliminating the manual `ffmpeg` pre-step.
- The CLI uses this helper. The GUI import path is left unchanged in this scope (it may
  later adopt the same helper to accept video, but that is out of scope here).

### 4. Transcription flow

The CLI constructs the live core services (FluidAudio transcription + diarization
services, `settings`, `FileSessionStore`) — the same wiring `AppDependencies.live()`
uses, minus GUI-only pieces.

- **Default (no `--register`):** use a temporary `FileSessionStore` rooted at a
  throwaway temp directory → `createSession` → `MediaAudioImporter` writes the (decoded)
  audio into the session dir → `ProcessingCoordinator.process(sessionId:)` → render the
  returned `TranscriptDocument` to `--out`/stdout → delete the temp directory. Nothing
  is left in the user's library.
- **`--register`:** use the real default `FileSessionStore` base URL → the session lands
  in the GUI library by construction → after `.ready`, run the shared `AutomaticExporter`
  (see §5) to write the md+json envelope to the configured export folder.

Diarization on/off, language, and speaker-count flags are forwarded to `process(...)`.

### 5. Shared auto-export (`AutomaticExporter`, small refactor)

Extract the envelope-writing logic currently inline in `AppViewModel` into a GUI-free
`Core/Export/AutomaticExporter` that takes `(SessionManifest, TranscriptDocument,
AutomaticMarkdownExportConfiguration)` and writes the `.md` + `.json` envelope (filename
from `AutomaticExportFileNameBuilder`, body from `MarkdownExportService`). Both the GUI
auto-export and the CLI `--register` path call it, keeping the lorre-ingest envelope
contract single-sourced.

### 6. App-state sync (known limitation)

If the GUI app is running during `--register`, the newly written session will not appear
until the app is relaunched/refreshed, unless `FileSessionStore` consumers already watch
the directory. **To verify during implementation:** whether the app file-watches the
session store. If not, this is documented as expected behaviour; live cross-process
refresh is explicitly out of scope (YAGNI).

## Data flow

```
input file (audio|video)
  └─> MediaAudioImporter (AVFoundation: extract/normalize audio)
        └─> FileSessionStore.createSession  (temp base | default base)
              └─> ProcessingCoordinator.process(sessionId:)  [FluidAudio: ASR + diarization]
                    └─> TranscriptDocument
                          ├─> render (MarkdownExportService) ─> --out / stdout
                          └─> [--register] AutomaticExporter ─> md+json envelope ─> export folder
                                                                                       └─> strongbad-lorre-ingest → Postgram → LinkedIn
```

## Testing

- **Unit**
  - `MediaAudioImporter`: a tiny `.mp4` (video) fixture and a `.m4a` fixture each decode
    to the expected audio format/parameters.
  - Entrypoint routing: argv → CLI vs GUI decision is a pure function, tested directly.
  - `AutomaticExporter`: produces the correct filename and md+json envelope for a known
    session/transcript (extends existing export coverage).
- **Regression:** existing ~75-test suite stays green.
- **Manual / integration**
  - `Lorre transcribe fixture.m4a` → transcript on stdout, nothing in library.
  - `Lorre transcribe fixture.mp4 --register` → session in store + envelope in folder.

## Risk & first step (spike)

Before building the rest, a spike must confirm that **FluidAudio/Parakeet runs when the
bundle binary is invoked as a CLI subprocess without `NSApplication`** (CoreML + ANE,
model cache download). Same bundle/signing as the GUI gives high confidence, but this is
the gating unknown and is the first implementation task.

## Out of scope

- Splitting into a standalone `LorreCore` library + separate `lorre` binary (approach B).
- Making the GUI import accept video files.
- Live cross-process refresh of the GUI library while the app is running.
- Any change to the downstream `strongbad-lorre-ingest` / Acquired consumers — they
  already consume the envelope contract this design reuses.
