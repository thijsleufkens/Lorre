# Lorre rebuild, milestone 2: Capture that cannot lose — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A recording exists on disk and in the database from the moment Start is pressed, survives a crash, force-quit or power loss, and is picked up again at the next launch. Recording is started from the menu bar and no longer needs the main window.

**Done when (from the spec):** killing the app mid-recording loses nothing, verified with injected failures.

**Architecture:** A new `LorreCapture` module takes over the two proven capture files (Process Tap system audio, audio utilities) and adds a slim `CaptureEngine` that streams each track straight into the conversation's folder. A `RecordingCoordinator` ties the engine to the `LorreCore` store: row and folder at Start, state change at Stop, nothing deleted on failure. A `RecordingRecovery` pass at launch turns abandoned recordings into `interrupted` conversations that can still be processed. Until per-track processing arrives in milestone 4, a small bridge in the existing target runs the current ASR pipeline on a finished conversation and writes the transcript into the database.

**Tech Stack:** Swift 6 / SwiftPM, AVFoundation, CoreAudio Process Tap, GRDB, SwiftUI `MenuBarExtra`, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-13-lorre-product-spec.md` (sections 4.4, 5, 7, 11). **Builds on:** `2026-11-13-lorre-rebuild-m1-foundation.md`.

---

## What is wrong today (verified in the code)

| Problem | Where |
|---|---|
| Tracks are written to `$TMPDIR/Lorre/recording-tmp/<uuid>.caf`; nothing links them to a session | `AVFoundationRecorderService.swift:501` |
| The session is created at Stop, after the audio | `AppViewModel.swift:591` |
| If Stop fails, the just-created session is deleted, and the recorder is cancelled, which removes the temp audio | `AppViewModel.swift:625`, `AVFoundationRecorderService.swift:1011` |
| A write failure on either track makes Stop throw before any file is moved | `AVFoundationRecorderService.swift:639` |
| A crash leaves two anonymous files in a folder macOS cleans up | the 8 Oct 2026 incident |

## Decisions taken for this milestone

| Decision | Reason |
|---|---|
| Move `ProcessTapSystemAudioCapture.swift` and `RecorderAudioUtilities.swift` into `LorreCapture`; write the microphone/orchestration part new | Those two files hold the hard-won findings and depend on nothing but two error cases. The 1,050-line recorder service is mostly live-preview machinery, which the new product does not have. |
| The old recorder service keeps compiling against the moved files and stays untouched otherwise | It is removed with the old UI in milestone 3; rewriting it now is wasted work. |
| One way to record: the menu-bar recorder. The old window's Start button is replaced by a pointer to it | Two recorders competing for the microphone is a new failure mode, and the old path is the one that loses recordings. |
| Tracks are named `microphone.caf` / `system-audio.caf` and written directly into `conversations/<id>/` | Recovery then needs no bookkeeping: the folder name is the conversation. |
| No mix at Stop. The mix is derived data, made when processing starts | Stop cannot fail on mixing, and a recovered recording follows the same path as a normal one. |
| Both tracks go through the timeline-aware writer (today `ProcessTapAudioWriter`) | Both are then anchored to the recording start, which milestone 4 needs for per-track transcription. |
| A `recording.lock` file with the process id marks a live recording | Lets recovery tell "being recorded right now" from "abandoned", also when the CLI runs next to the app. |
| The processing bridge reuses the existing pipeline through a temporary `FileSessionStore`, like `transcribe --register` does | No change to `ProcessingCoordinator`; the bridge disappears in milestone 4. It also keeps the automatic export running, so the downstream pipeline keeps receiving transcripts during the rebuild. |
| New conversations are not shown in the old window | They appear in the menu-bar panel, open as a Markdown transcript, and are listed by the CLI. The review screen replaces all of this in milestone 3. |

## File structure

- Modify `Package.swift` — `LorreCapture` + `LorreCaptureTests` targets; `Lorre` depends on `LorreCapture`.
- Move to `Sources/LorreCapture/`: `ProcessTapSystemAudioCapture.swift`, `RecorderAudioUtilities.swift` (with `git mv`).
- Create `Sources/LorreCapture/CaptureError.swift`, `CaptureSource.swift`.
- Create `Sources/LorreCapture/TimelineAudioWriter.swift` — renamed from `ProcessTapAudioWriter`.
- Create `Sources/LorreCapture/CaptureEngine.swift` — protocol + live implementation.
- Create `Sources/LorreCapture/RecordingLock.swift`.
- Create `Sources/LorreCapture/RecordingCoordinator.swift`.
- Create `Sources/LorreCapture/RecordingRecovery.swift`.
- Create `Sources/LorreCapture/SleepGuard.swift`.
- Modify `Sources/LorreCore/Store/Schema.swift` — migration `v2`.
- Modify `Sources/LorreCore/Domain/Conversation.swift`, `Store/ConversationStore.swift`.
- Create `Sources/LorreCore/Import/LegacyTranscriptMapper.swift` — shared by the importer and the bridge.
- Create `Sources/Lorre/Bridge/ConversationProcessor.swift`, `ProcessingQueue.swift`.
- Create `Sources/Lorre/Features/MenuBar/RecorderModel.swift`, `MenuBarRecorderView.swift`.
- Modify `Sources/Lorre/App/LorreApp.swift` — `MenuBarExtra` scene, recovery at launch.
- Modify `Sources/Lorre/Features/Recorder/RecorderStageViews.swift` — replace the Start pane.
- Modify the call-prompt action in `AppViewModel.swift` to start through the coordinator.
- Create `Sources/Lorre/CLI/ShowCommand.swift`, `ProcessCommand.swift`, `CaptureSelfTestCommand.swift`.
- Create tests under `Tests/LorreCaptureTests/`, extend `Tests/LorreCoreTests/`.

---

## Task 1: `LorreCapture` module with the moved files

- [x] Add the targets to `Package.swift`: `LorreCapture` depends on `LorreCore`; `LorreCaptureTests` depends on `LorreCapture`; add `"LorreCapture"` to the `Lorre` target.
- [x] `git mv` the two files. Create `CaptureError`:

```swift
public enum CaptureError: Error, Equatable, Sendable, LocalizedError {
    case startFailed(String)
    case stopFailed(String)
    case permissionDenied(String)
    public var errorDescription: String? { … the message … }
}
```

  Replace `LorreError.recordingStartFailed` / `.recordingStopFailed` in the moved files with it.
- [x] Make public exactly what the old recorder service uses (the capture class, its start/stop/`writeFailure`, the writer, `RecorderAudioUtilities.mixToCanonicalFile`, the `AVAudioPCMBuffer` helpers). Nothing else.
- [x] In `AVFoundationRecorderService`, `import LorreCapture` and translate `CaptureError` back to the matching `LorreError` case at the call sites, so the old UI's error messages are unchanged.
- [x] `git mv` `RecorderAudioMixTests.swift` and `ProcessTapWriterTimelineTests.swift` to `Tests/LorreCaptureTests/` and adjust imports.
- [x] Full test run: the total count equals the count after milestone 1 (159). Build the app, make one mic+system recording with the **old** Start button and confirm both stems contain audio: this is a pure move and must not change behaviour.
- [x] Commit: `refactor: move Process Tap capture and audio utilities into LorreCapture`.

## Task 2: Timeline writer for every track

- [x] Rename `ProcessTapAudioWriter` to `TimelineAudioWriter` (keep a `typealias` for the old name until the old recorder is removed). Its behaviour is unchanged: t=0 is the anchor date, delivery gaps above 0.35 s are padded with silence.
- [x] Add tests to `TimelineWriterTests` (the moved file): a writer anchored at T receiving its first buffer at T+2 s starts with 2 s of silence; buffers arriving back to back add no padding; after `close()` the file's frame count equals padded plus written frames; a write after a simulated failure reports the failure through `failureMessage()` and does not crash.
- [x] Add `flush()`: `AVAudioFile` offers no explicit sync, so the writer keeps a `FileHandle` on the same URL and calls `synchronize()` at most once per second from the write path. This bounds what a power loss can cost to about a second. Test that `flush()` is throttled.
- [x] Commit: `feat(capture): one timeline-anchored writer for all tracks`.

## Task 3: Does a killed writer leave a readable file? (measure first)

The recovery design rests on a `.caf` that was never closed still being readable. The 8 Oct recovery suggests it is; this task proves it or changes the design.

- [x] Add a hidden CLI command `capture-selftest --out <file> --seconds N` (`shouldDisplay: false`) that writes a sine wave through `TimelineAudioWriter` in real-time-sized buffers and never closes the file.
- [x] Test `KilledWriterTests` in `LorreCaptureTests`: launch the built `Lorre` binary with that command as a subprocess, wait 3 s, send `SIGKILL`, then open the file with `AVAudioFile(forReading:)` and assert that it opens and holds at least 2 s of audio with the expected peak level. Skip (not fail) when the binary is not built.
- [x] **If the test passes:** record the measured loss (seconds missing at the end) in this plan.
- [x] **If it fails:** add `AudioFileRepair.repairIfNeeded(_:)` that rewrites the CAF data-chunk size from the file length (the header is otherwise intact because the format is written first), make the test pass through it, and have recovery (Task 6) call it before reading any track.
- [x] Commit: `test(capture): a writer killed mid-recording leaves recoverable audio`.

## Task 4: `CaptureEngine`

```swift
public enum CaptureSource: String, Codable, CaseIterable, Sendable { case microphone, systemAudio, microphoneAndSystemAudio }

public struct CaptureStart: Sendable { public var startedAt: Date; public var trackFiles: [TrackKind: String] }
public struct CaptureStop: Sendable {
    public var endedAt: Date
    public var durationSeconds: Double
    /// Tracks whose writer reported an error. Their files are kept as far as they got.
    public var trackFailures: [TrackKind: String]
}

public protocol CaptureEngine: Sendable {
    func start(source: CaptureSource, into folder: URL) async throws -> CaptureStart
    func stop() async -> CaptureStop
    func levels() async -> [TrackKind: Double]
}
```

- [x] Implement `LiveCaptureEngine` (an actor). The microphone part is ported from `AVFoundationRecorderService.startMicrophoneCapture` with the three voice-processing findings kept verbatim, comments included: voice processing only in mic+system mode with ducking at `.min`; more than two input channels reduced to channel 0; the tap's buffer sizing. It writes through `TimelineAudioWriter` anchored at the recording start. System audio uses `ProcessTapSystemAudioCapture` as today, writing to `system-audio.caf` in the folder. No live transcription, no preview mixer.
- [x] `stop()` never throws: it stops both pipelines, closes both writers, and reports failures per track. A failure on one track does not affect the other.
- [x] Start is all-or-nothing: if the second pipeline fails to start, the first is stopped and the files it created are removed, then the error is thrown. At that point nothing worth keeping has been captured.
- [x] Microphone device changes: observe `AVAudioEngineConfigurationChange`; restart the engine and re-install the tap, continuing into the same writer. The timeline writer pads the gap, so the track stays aligned. Log the event.
- [x] Hold a `SleepGuard` (`ProcessInfo.beginActivity` with `.userInitiated` and `.idleSystemSleepDisabled`) from start to stop.
- [x] Unit-test what can run without hardware: `CaptureSource` → expected track kinds and file names; `SleepGuard` begin/end balance. The engine itself is verified manually in Task 10, as `CLAUDE.md` prescribes for audio capture.
- [x] Commit: `feat(capture): engine that streams tracks into the conversation folder`.

## Task 5: Schema v2 and the recording lock

- [x] Migration `v2` in `Schema.swift` (a new migration, `v1` is not edited): `ALTER TABLE conversation ADD COLUMN lastError TEXT;` and `ALTER TABLE conversation ADD COLUMN captureSource TEXT;`. Add both as optional properties on `Conversation`.
- [x] Tests: a database created at `v1` (build one by running only the first migration) upgrades and keeps its rows; the new fields round-trip; `DomainRawValueTests` pins `CaptureSource`.
- [x] Add to `ConversationStore`: `conversations(inState:)`, `setState(_:lastError:for:)`, `folder(for:paths:)` returning `conversations/<UUID>/`. Tests for each.
- [x] `RecordingLock`: `write(in folder:, pid:)`, `read(in:)`, `remove(in:)`, and `isLive(in:)` which is true only when the lock exists and `kill(pid, 0)` says that process is alive. Tests: no lock → not live; own pid → live; a pid that does not exist → not live; an unreadable lock → not live.
- [x] Commit: `feat(core): schema v2 for capture state; recording lock`.

## Task 6: `RecordingCoordinator`

```swift
public actor RecordingCoordinator {
    public init(paths: LorrePaths, database: LorreDatabase, engine: any CaptureEngine, now: @escaping @Sendable () -> Date = { Date() })
    public func start(source: CaptureSource, title: String? = nil) async throws -> Conversation
    public func stop() async throws -> Conversation
    public var active: Conversation? { get }
    public func levels() async -> [TrackKind: Double]
}
```

Order of operations, which is the whole point:

| Step | Start | Stop |
|---|---|---|
| 1 | Create the folder | Stop the engine (cannot throw) |
| 2 | Insert the conversation (`recording`, title default `Conversation <date>`) and its `Track` rows | Read duration from the result |
| 3 | Write the lock | Remove the lock |
| 4 | Start the engine | State → `processing`; or `interrupted` with `lastError` when a track failed and no track has audio |
| 5 | On engine failure: remove the row, the lock and the (empty) folder; rethrow | A track failure with at least one good track still goes to `processing`, with `lastError` describing what is missing |

- [x] Test first with a `FakeCaptureEngine` (`Tests/LorreCaptureTests/RecordingCoordinatorTests.swift`):
  - after `start`, the conversation exists in state `recording`, its folder exists, its track rows match the source, and the lock is live;
  - engine start failure leaves no row, no folder and no lock, and the error reaches the caller;
  - `stop` moves the conversation to `processing` with the engine's duration and removes the lock;
  - `stop` with one failed track and one good track → `processing`, `lastError` set, both files still on disk;
  - `stop` with every track failed or empty → `interrupted`, files still on disk;
  - a second `start` while recording throws and does not disturb the first;
  - `stop` without a recording throws;
  - **no code path in the coordinator deletes an audio file** except the engine-start failure in step 5 (assert by giving the fake engine files of non-zero size and checking they survive every failure case).
- [x] Implement, then commit: `feat(capture): recording coordinator that never drops audio`.

## Task 7: `RecordingRecovery`

```swift
public struct RecoveryReport: Equatable, Sendable {
    public var recovered: [UUID]      // recording → interrupted
    public var adopted: [UUID]        // folder with audio but no row → new interrupted conversation
    public var requeue: [UUID]        // already `processing`, to be processed again
    public var stillLive: [UUID]      // a live lock; left alone
}
public struct RecordingRecovery: Sendable {
    public init(paths: LorrePaths, database: LorreDatabase)
    public func run() throws -> RecoveryReport
}
```

- [x] Test first (`RecordingRecoveryTests.swift`), building real folders and small real `.caf` files in a temp root:
  - a `recording` conversation with a stale lock becomes `interrupted`, gets its duration from the longest track, and loses the lock;
  - a `recording` conversation with a live lock is reported as `stillLive` and not changed;
  - a `recording` conversation with no lock at all becomes `interrupted`;
  - a folder under `conversations/` with audio and no row is adopted: a conversation with the folder's UUID, `startedAt` from the oldest file's creation date, tracks from the known file names;
  - a folder that is not a UUID, or has no audio, is ignored;
  - a zero-byte or unreadable track is kept as a row and does not stop recovery of the other track;
  - conversations in `processing` are returned in `requeue`;
  - running recovery twice changes nothing the second time.
- [x] Implement; if Task 3 produced `AudioFileRepair`, call it before reading durations.
- [x] Commit: `feat(capture): recover abandoned recordings at launch`.

## Task 8: Processing bridge (temporary, until milestone 4)

- [x] Extract the transcript mapping from `LegacySessionImporter` into `LegacyTranscriptMapper.insert(transcriptJSON:conversationId:into:)` in `LorreCore`, used by the importer and the bridge. The importer tests must stay green unchanged.
- [x] `ConversationProcessor` in the `Lorre` target, modelled on `TranscribeCommand`'s register path:
  1. pick the input: `microphone.caf` + `system-audio.caf` → `RecorderAudioUtilities.mixToCanonicalFile` into `mix.caf` in the conversation folder (add a `mix` track row); a single track is used as is;
  2. import that file into a temporary `FileSessionStore`, run `ProcessingCoordinator`, read the resulting `transcript.json`;
  3. write it to the database through the mapper as the current transcript version; write `transcript.md` into the conversation folder with `MarkdownExportService`;
  4. run the automatic export when the user has it configured, so the downstream pipeline keeps receiving conversations;
  5. state → `proposed`, `lastError` cleared; on failure the state stays `processing`, `lastError` is set, and the audio is untouched.
- [x] `ProcessingQueue` (an actor): one conversation at a time, in arrival order; `enqueue(_:)`, and an `AsyncStream` of state changes for the UI.
- [x] Tests with the existing mock transcription/diarization services (`MockProcessingServices`): a conversation with two tracks gets a mix, a transcript version, segments and state `proposed`; a failing transcription leaves `processing` + `lastError` and every audio file in place; two enqueued conversations are processed in order; an `interrupted` conversation with audio can be processed and ends as `proposed`.
- [x] Commit: `feat: process recorded conversations into the database (bridge)`.

## Task 9: Menu-bar recorder, launch recovery, CLI

- [x] `RecorderModel` (`@MainActor @Observable`): states `idle`, `starting`, `recording(since:)`, `stopping`; `source` (remembered in `UserDefaults`); `levels`; `recent: [ConversationSummary]` (last five); `start()`, `stop()`. It owns the coordinator and the queue. Unit-test the state machine with the fake engine: start → recording → stop → idle; a start error returns to idle with a message; stop enqueues the conversation.
- [x] `MenuBarRecorderView` in a `MenuBarExtra` (window style): source picker (Microphone / Microphone + system audio), a Start button; while recording: elapsed time, a level bar per track, Stop; a one-line reminder at start ("Let the other person know this is being recorded"); below, the recent conversations with their state (`processing…`, `ready`, `interrupted`) and per row **Open transcript** (opens `transcript.md`) or **Process** for an interrupted one. The menu-bar icon shows a filled dot while recording. Use Sage tokens only; add tokens to `DesignSystem.swift` if one is missing.
- [x] In `LorreApp`: build the database, coordinator, queue and `RecorderModel` once; at launch run `RecordingRecovery`, enqueue `requeue`, and if anything was recovered or adopted show a notification "A recording was interrupted and has been recovered" that opens the menu-bar panel. The app must keep running, and recording, with every window closed.
- [x] Replace the Start pane in `RecorderStageViews.swift` with a short text and a button that opens the menu-bar panel. Remove the old window's entry points to `startRecordingTapped` (the method and the old recorder stay until milestone 3, unused). Point the call-detection prompt's Record action at `RecorderModel.start()`.
- [x] A system notification when processing finishes: "Your conversation is ready", opening the transcript.
- [x] CLI: `Lorre show <id> [--json]` prints the current transcript with speaker names and timestamps; `Lorre process <id>` runs the bridge for one conversation (models load in-process, like `transcribe`). Register both in `CLIRouting`. Test the rendering function of `show`.
- [x] Commit: `feat: menu-bar recorder with recovery at launch`.

## Task 10: Failure injection and manual verification

Automated (added to the suites above, listed here as the acceptance set):

- [x] engine start failure → nothing left behind;
- [x] writer failure on one track → the other track complete, conversation processed with a note;
- [x] database write failure at Stop (close the database before `stop`) → audio on disk, and the next `RecordingRecovery.run()` on a fresh database handle finds it;
- [x] process killed while writing (Task 3) → audio readable;
- [x] recovery with stale lock, no lock, live lock, orphan folder.

Manual, by Thijs, with the packaged app (record the outcome of each in this plan):

- [ ] **Normal:** mic + system recording of a short call or a video playing; Stop; notification arrives; transcript opens; `Lorre list` shows it as `proposed`.
- [x] **Force-quit:** start a mic + system recording, speak for 30 s with audio playing, run `kill -9` on Lorre. Relaunch. Expected: a notification about a recovered recording; the conversation is `interrupted` with about 30 s duration; **Process** produces a transcript containing what was said.
- [ ] **Window closed:** start recording, close the main window, keep talking, stop from the menu bar. Nothing is lost.
- [ ] **Microphone switched:** plug in or unplug a headset mid-recording. The recording continues and the transcript covers both halves.
- [ ] **Sleep:** leave a recording running for 10 minutes without touching the Mac; it does not sleep and the track is complete.
- [ ] **Old sessions:** the old window still lists and plays the 12 existing sessions.
- [x] `./scripts/ci_check.sh` passes; update `CLAUDE.md` (the `LorreCapture` module and its rule: nothing in it may delete a track; where recordings live; the menu-bar recorder; the bridge being temporary) and the "Persistence" and "Architecture" sections that describe the old temp-folder flow.
- [x] Commit: `docs: capture module, recovery and the menu-bar recorder`.

---

## Execution notes (2026-11-13)

Done: tasks 1–9 and the automated part of task 10. Open: five manual checks (marked above).

**Measured**

- A writer killed with `SIGKILL` leaves readable audio: 3.2–3.6 s readable after a kill at about 4 s
  (the difference is process start-up plus the last unsynced stretch). No repair step was needed.
- End to end with the packaged app and the real models, on a simulated abandoned recording (100 s cut
  from the 8 Oct stems): `recover` → `process` (4 s) → `proposed`, 26 segments.
- End to end through the app itself: a microphone + system recording was started from the window,
  the process was killed with `kill -9` after 27 s, the app was started again. The recording was
  recovered and transcribed without any action (state `proposed`, transcript on disk).
- Tests: 229 (138 in `LorreTests`, 45 in `LorreCaptureTests`, 46 in `LorreCoreTests`), all passing.

**Found while testing, and fixed**

- The first recording after installing a new build contained 27 s of digital silence on the
  microphone track; the second recording, minutes later, was fine. The likely cause is macOS
  withholding the microphone from a newly signed build until permission is settled; this was not
  confirmed. The engine now detects a microphone that delivers only zeros, the recorder says so
  within three seconds, and such a recording is not sent for transcription.
- `ProcessTapSystemAudioCapture.writeFailure()` always returned nil after `stop()`, because the
  writer had been released by then. The failure is now kept.
- Processing an imported conversation would have written the mix and transcript into the old
  session folder. All output now goes to `conversations/<id>/`.

**Deviations from the plan**

- `CaptureSource` lives in `LorreCore` (the store records it), not in `LorreCapture`.
- Recovered recordings are queued for transcription automatically instead of waiting for a click.
- Added `Lorre recover` (the plan only had it implicitly) and `Lorre process --no-export`.
- The menu-bar panel cannot be opened programmatically, so the old window's pane keeps a
  Start/Stop button that drives the new recorder, next to the explanation.
- No separate "interrupted" confirmation dialog; the panel's message and a notification carry it.

**Not verified**

- System audio in the new path. During the test the system track stayed empty: the test sound was
  started after the recording, and the tap only includes processes that were already producing audio
  (the limitation documented in `CLAUDE.md`). A real call must confirm it.
- The menu-bar panel was not looked at on screen; its model is tested, the view is not.
- Microphone switch, sleep prevention and the window-closed case.

## Out of scope for this milestone

- The review screen and Today (milestone 3). New conversations are reachable only through the menu-bar panel, the Markdown transcript and the CLI until then.
- Per-track transcription and the speaker work (milestone 4). The bridge still transcribes the mix.
- Calendar matching at Start (milestone 4, with the names).
- Removing the old recorder service, the old window and the old store (milestone 3).
- Importing from upstream: its recovery works on the old store and the old recorder, so only the ideas carry over (session folder at Start, restoring the mix from surviving stems, a sleep guard), not the code.

## Risks

| Risk | Handling |
|---|---|
| The new microphone path regresses one of the voice-processing fixes | The code is ported, not rewritten, with its comments; Task 1 and Task 10 each include a real mic+system recording with a check that both tracks contain sound. |
| An unclosed `.caf` is not readable | Task 3 measures it before anything depends on it, with a defined fallback. |
| Two recorders in one process during the transition | The old entry points are removed in Task 9; the coordinator refuses a second start. |
| The bridge runs models while the old window also processes | `ProcessingQueue` is the only caller after Task 9, since the old window can no longer start recordings; imports through the old window's file picker remain possible and are rare — noted, not solved. |
| Recovery mislabels a live recording | The lock with a pid check; the `stillLive` test. |
| A menu-bar app that cannot be tested in unit tests | The model's state machine is tested; the view is thin. |
