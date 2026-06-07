# Lorre Feature Backlog

A working backlog of features for upcoming releases of this Lorre fork.

**Product focus:** Lorre is a best-in-class **local transcription app**. It
captures meetings, produces accurate, well-structured transcripts with speaker
labels, and hands the result off cleanly to wherever the user wants to think
about it (Claude Code, Cowork, Notion, their own notes app). The app itself
does not summarize, rewrite, or "understand" content - that work is
deliberately delegated to external tools where the user already has strong
LLMs and existing subscriptions.

This focus keeps Lorre fast, predictable, and privacy-friendly, and avoids the
quality ceiling of small on-device LLMs.

Each item lists rough **Impact** (1-5), **Effort** (S/M/L/XL) and a **Horizon**
(Now / Next / Later). Items are not yet ordered or committed to a release.

---

## Explicitly out of scope

To keep the product focused, the following are intentionally **not** on the
roadmap:

- AI-generated summaries, recaps, or "smart notes"
- Augmented / rewritten notes ("Granola mode")
- Action item or decision extraction
- Chat-with-transcript ("Ask Lorre")
- Auto-chapters or topic detection via LLM
- Real-time meeting coach
- Any bundled LLM provider, hosted or local

These belong in the tools the user already pays for and trusts. Lorre's job
is to produce the cleanest possible source material for those tools.

---

## Theme 1 - Auto-record scheduled Teams meetings (headline, deferred)

**Status:** scoped, not yet implemented. Sized for after the export
hand-off (Theme 8) lands so this feature can flow transcripts directly
into the user's external AI tools.

**User story for this fork:** "Every Teams meeting on my calendar gets
captured by Lorre without me thinking about it, and only the actual
conversation gets recorded - not the pre-call dead air while people are
joining."

The single biggest workflow win for the primary user: never forget to
start recording. Scheduled Teams calls dominate this fork's real-world
usage, so V1 narrows hard on that case and leaves ad-hoc detection and
other platforms for a follow-up.

### V1 scope

- **Calendar-driven arming (EventKit)** - The strongest predictive
  signal. With calendar permission, Lorre watches for events whose
  description or location field contains a Teams meeting link
  (`teams.microsoft.com/l/meetup-join/...` or the legacy `teams.live.com`
  patterns). When an event window opens (default: 5 minutes before
  scheduled start), Lorre transitions into **Armed** state - watching,
  not yet recording. Impact 5, Effort M.
- **Teams call-state detection** - Once Armed, watch for evidence that
  the meeting has actually started. Sources, in order of reliability:
  Teams process running (`com.microsoft.teams2` / `com.microsoft.teams`)
  AND default input device input level sustained above noise floor for
  more than N seconds (default 8s), with audio output routed through a
  device used by Teams. Direct "is in call" state is not exposed by
  Teams as a public API, so this is a composite signal. Impact 5,
  Effort M.
- **Activity-driven stop** - Stop is **not** calendar-driven. Watch for
  sustained mic silence (>30s default) AND Teams audio routing
  dropping, then transition to **Cooling Down** for a grace period
  (default 60s) before saving. Cooling Down resumes recording if audio
  comes back. Impact 4, Effort S.
- **Per-calendar rules** - "Always record meetings on calendar X",
  "Ask first", "Never". Defaults to Ask. Stored in settings keyed by
  EventKit calendar identifier. Impact 4, Effort S.
- **Manual override always wins** - Manual record during Armed state
  takes precedence, cancels the auto-arm watcher for that event.
  Manual stop during auto-record ends the session normally without
  the cooling-down dance. Impact 4, Effort S.
- **Persistent armed indicator** - Menu-bar status item shows current
  state (Idle / Armed / Recording / Cooling Down) so the user can
  notice and intervene if start detection fails. Impact 4, Effort S.
- **Pre-flight check at auto-start** - Before committing to the
  recording, run a 1s mic + screen-recording-permission check. If
  permissions are missing, surface a one-click prompt instead of
  silently recording nothing. Impact 4, Effort S.

### Timing model (the hard part)

The "scheduled start time" and "actual conversation start" are rarely
the same. Two state machines, deliberately separated:

**Arming state machine** (driven by calendar)
- Idle -> Armed: event with Teams link enters its window
  (start - 5 min)
- Armed -> Armed (extended): event has passed scheduled start but no
  start signal yet. Keep watching until scheduled end + 30 min
  (configurable). This is the "everybody is 10 minutes late" case.
- Armed -> Idle: extended window elapsed without a start signal.
  Optionally log a missed-meeting event for the user.
- Armed -> Recording: start detection fires (see below).
- Armed -> Manual: user starts recording manually inside the window.

**Recording state machine** (driven by audio + process state)
- Armed -> Recording: composite start signal sustains for N seconds.
  Composite = (Teams process active) AND (mic level above noise floor)
  AND (it is OK to start by per-calendar rule; otherwise prompt
  first).
- Recording -> Cooling Down: composite stop signal sustains for M
  seconds. Composite = (mic silent) AND (Teams audio routing
  inactive).
- Cooling Down -> Recording: activity resumes within grace period.
- Cooling Down -> Saved: grace period elapsed. Session is finalized
  and exported per existing pipeline.

### Edge cases to design for explicitly

1. **Late start.** Meeting at 10:00 actually begins at 10:12. Lorre
   stays Armed past the scheduled start; uses the +30 min extended
   window. This is the most common case for the primary user.
2. **Late finish.** Stop is activity-based, not calendar-based. The
   scheduled end is informational only.
3. **Join early, then wait.** User joins at 10:00 and waits alone for
   5 minutes. No sustained 2-way conversation, so V1 still treats the
   user's mic activity (greetings, "hi, can you hear me") as a start
   signal. Accepted tradeoff: a few minutes of "is this thing on"
   might be recorded. Future refinement could try to detect a second
   voice before starting.
4. **Back-to-back meetings.** 10:00 - 11:00 followed by 11:00 - 12:00,
   both Teams. The first session's audio overflows past 11:00 by a
   few minutes. V1 keeps recording the same session until activity
   drops, then transitions the second event from Armed straight to
   Recording when activity picks up again. Splitting one continuous
   recording into two sessions is explicitly out of V1 scope.
5. **User joins late.** Meeting 10:00 - 11:00, user joins at 10:20. No
   audio before 10:20 is available locally anyway. Recording starts
   when start detection fires post-10:20. Earlier scheduled time is
   recorded in the manifest for context only.
6. **Manual start during Armed.** Auto-arm watcher cancels for this
   event. No double-start.
7. **Manual start outside any Armed window.** Existing flow. No change.
8. **Failed start detection.** Meeting actually started but composite
   signal never fires (Teams crashed, mic muted, etc). Menu-bar
   indicator stays on Armed; user can notice and click record. Add a
   one-shot "Are you in a meeting? Lorre is armed but hasn't detected
   the start." notification 5 minutes after scheduled start, only if
   nothing has fired.
9. **Cancelled / declined event.** EventKit reports event status.
   Skip Armed transition for declined events; respect last-modified
   for late cancellations.
10. **Permissions revoked mid-flight.** Calendar or mic permission
    revoked after Armed. Transition to Idle and surface a one-time
    notification.
11. **System sleep / lid close during Armed or Recording.** Recording
    stops on sleep (AVFoundation behavior). On wake inside the event
    window, re-arm; outside, transition to Idle. Document the gap in
    the session manifest.
12. **Multiple Teams calls in parallel.** Rare but possible (user has
    Teams open for two tenants). V1 records the active default input
    device only; second simultaneous call is missed. Out of V1 scope.

### Open design questions

- **Start signal weight.** Is mic activity alone (without Teams
  process) enough to start? Probably no for this feature - the whole
  point is "Teams meeting" - but worth confirming. The non-Teams
  ad-hoc case belongs to the later expansion below.
- **Calendar source.** EventKit aggregates iCloud, Google Calendar
  (when connected to macOS Calendar), and Exchange / Microsoft 365
  (when connected). For users on Outlook desktop only, EventKit may
  not see the events. Document the supported configurations and
  detect the "no calendars contain Teams links" empty state.
- **Audio of the other side.** Capturing system audio requires Screen
  Recording permission. Without it, auto-record gets only the user's
  voice. Pre-flight check must catch this; settings must make the
  cost of skipping system audio explicit.
- **Privacy mode interaction.** Auto-records should default to the
  user's current privacy-mode setting. No surprise behavior. Confirm
  in onboarding.
- **What constitutes "noise floor"?** A fixed dB threshold is fragile
  across hardware. Probably needs a short calibration on first run
  (existing pre-flight infrastructure could feed this).
- **Configurability vs sensible defaults.** Every threshold above
  (5 min pre-arm, 30 min post-end, 8s sustain, 30s silence, 60s
  cooling) is tunable. V1 should ship sensible defaults and hide the
  tunables behind an Advanced section.

### Later expansion (out of V1 scope)

- **Other platforms.** Zoom, Google Meet (browser), Slack huddles,
  FaceTime. Each needs its own process-state detection. Worth
  shipping once the Teams flow is proven.
- **Ad-hoc call detection without a calendar event.** Mic-claim
  polling for known meeting apps, with the same composite-signal
  pattern. Useful for users whose calls are unplanned. Not the
  primary use case for this fork.
- **Browser-based Meet detection.** Distinguishing "Chrome is in a
  meet.google.com tab" from "Chrome is doing anything else" needs
  either Accessibility API (window titles) or a browser extension.
  Material effort; defer.
- **"Recording started 4 minutes after meeting began" warning.** If
  start-detection latency is high, offer to mark the gap in the
  manifest so downstream tools know.
- **Multi-tenant Teams or parallel calls.** Rare and intricate.

## Theme 2 - Transcript quality and editing

The current `TranscriptSegment` model and review UI is solid; this theme
makes it pleasant to clean up and trust.

- **Confidence-based review queue** - Highlight low-confidence segments
  (uses `confidence` already on `TranscriptSegment`) and offer a "Review next
  uncertain segment" command. Impact 4, Effort S, Horizon Now.
- **Diarization touch-ups** - Drag a divider to split a segment or merge
  consecutive segments; bulk reassign a contiguous range to a speaker.
  Impact 4, Effort M, Horizon Now.
- **Word-level timing edits** - Use the `tokenTimings` already produced by
  the ASR pipeline to support tap-to-play on a specific word and word-level
  redaction. Impact 3, Effort M, Horizon Next.
- **Find and replace in transcript** - Scoped to one session or all
  sessions, with regex option. Useful for fixing recurring brand or
  acronym misrecognitions. Impact 3, Effort S, Horizon Now.
- **Custom vocabulary per session / folder** - Extend the existing
  `VocabularyBoostingConfiguration` to support per-folder glossaries and
  shared team glossaries (JSON import/export). Impact 4, Effort S, Horizon
  Now.
- **PII / redaction tool** - Detect and one-click redact emails, phone
  numbers, card numbers, addresses using regex + the existing token
  timings; redacted spans persist in the transcript and exports. No LLM
  needed. Impact 4, Effort M, Horizon Next.
- **Versioned transcripts** - Lightweight history of edits per session
  with diff view and revert. Impact 3, Effort M, Horizon Later.

## Theme 3 - Speaker identity

Lorre already ships speaker enrollment via FluidAudio; this theme makes the
identity layer cross-session and trustworthy.

- **Auto-identify enrolled speakers on new sessions** - Match diarized
  speakers to the `KnownSpeakerStore` at the end of processing, with a
  confirm step for borderline matches. Impact 5, Effort M, Horizon Now.
- **Speaker fingerprint management UI** - Browse enrolled speakers, listen
  to reference clips, merge two profiles, re-enroll with a new sample.
  Impact 3, Effort S, Horizon Now.
- **Talk-time analytics** - Per-speaker speaking time, longest monologue,
  talk ratio. Plain stats, no inference. Surfaced on session detail and in
  exports. Impact 3, Effort S, Horizon Next.
- **Cross-session speaker view** - "Show all sessions where Maria spoke".
  Pure filter on stored speaker IDs, no AI. Impact 3, Effort M, Horizon
  Later.

## Theme 4 - Organization and search

- **Full-text search across all sessions** - Index transcripts and notes
  with on-device search (CoreSpotlight or a small sqlite FTS5 store).
  Filter by speaker, date range, folder, language. Impact 5, Effort M,
  Horizon Now.
- **Bookmarks during recording** - Press a hotkey or click a button to
  mark a moment with an optional short label. Bookmarks aggregate into a
  per-session list and are included in exports. Impact 4, Effort S,
  Horizon Now.
- **Smart folders / saved searches** - Folders defined by a query rather
  than manual assignment. Builds on the existing `SessionFolder` model.
  Impact 3, Effort M, Horizon Next.
- **Tags and colors** - Free-form tags on sessions with autocomplete from
  prior tags. Impact 2, Effort S, Horizon Next.
- **Quick-jump to attendees / topics** - Sidebar surfaces recent attendees
  (from calendar metadata) and recent folders for one-click filtering.
  Impact 2, Effort S, Horizon Next.

## Theme 5 - Capture experience

- **Floating recording HUD** - Compact always-on-top widget with mic
  level, elapsed time, pause, stop, and a "bookmark this moment" button.
  Survives full-screen apps. Impact 4, Effort M, Horizon Now.
- **Menu bar quick record** - One-click record from the menu bar without
  opening the main window; uses the last-used source. Impact 4, Effort S,
  Horizon Now.
- **Pause and resume** - Pause/resume mid-recording with a visible gap in
  the resulting waveform and transcript. Impact 4, Effort M, Horizon Now.
- **Global hotkeys** - Configurable shortcuts for start/stop, pause,
  bookmark, toggle live preview. Impact 3, Effort S, Horizon Next.
- **URL scheme** - `lorre://record?source=mic&folder=customer-calls` for
  Shortcuts, Raycast, Stream Deck. Impact 2, Effort S, Horizon Next.
- **Scheduled recordings** - Start a recording at a fixed time, or X
  minutes before a calendar event. Mostly subsumed by Theme 1 once
  auto-record lands. Impact 2, Effort M, Horizon Later.

## Theme 6 - Audio pipeline

- **Noise suppression pre-pass** - Optional pre-processing stage (Apple's
  `AVAudioUnitVoiceProcessing` or a small CoreML denoiser) before ASR for
  noisy environments. Impact 3, Effort M, Horizon Next.
- **Loudness normalization** - Apply EBU R128 loudness target on playback
  and on export to keep mixed mic+system audio comfortable. Impact 2,
  Effort S, Horizon Next.
- **Background processing queue UI** - Show a queue and per-job progress
  for batch imports; `ProcessingCoordinator` already emits the events, the
  UI just needs surfacing. Impact 3, Effort S, Horizon Now.
- **Resumable processing** - If the app quits during transcription, resume
  from the last persisted chunk rather than restarting. Impact 3, Effort
  M, Horizon Later.
- **Speaker-aware live preview** - Today the live preview shows an active
  speaker hint; extend it to show a rolling per-speaker color stripe so
  the user can see who is talking in real time. Impact 3, Effort S,
  Horizon Now.

## Theme 7 - Translation (deterministic only)

Parakeet covers 25 European languages. Translation in Lorre stays
deterministic - Apple's Translation framework on-device, no LLM. If the
user wants nuance, they translate in their preferred external tool.

- **Inline translated view** - Show the transcript translated to the
  user's preferred language alongside the source, with a toggle. Apple
  Translation only; no provider if unavailable. Impact 3, Effort M,
  Horizon Next.
- **Translated subtitle export (SRT / VTT)** - Useful for video producers
  and accessibility. Impact 3, Effort S, Horizon Next.
- **Language switch detection within a session** - Detect language
  changes mid-recording (e.g. NL -> EN halfway through a call) and label
  sections. Helps downstream tools. Impact 2, Effort M, Horizon Later.

## Theme 8 - Export and external AI workflows

This is where Lorre meets Claude Code, Cowork, and the rest of the user's
toolchain. The goal is to make Lorre the easiest source of clean
transcripts for external thinking tools.

- **Rich JSON export** - Stable, well-documented JSON schema with speaker
  IDs, timings, confidence, bookmarks, attendees, language - everything an
  external LLM needs as context. Versioned and self-describing. Impact 5,
  Effort S, Horizon Now.
- **Subtitle export (SRT / VTT)** - Straightforward addition next to the
  existing `ExportFormat` enum. Impact 3, Effort S, Horizon Now.
- **"Copy as Markdown for Claude" command** - One-click copy a transcript
  formatted as a clean Markdown prompt (front-matter with metadata,
  speaker-prefixed lines, bookmarks as headings). Optimized for pasting
  into a Claude Code session or any chat. Impact 5, Effort S, Horizon Now.
- **Reveal in Finder + drag-out** - Drag a session from the sidebar onto
  any app to drop the JSON + Markdown bundle. Impact 3, Effort S, Horizon
  Now.
- **Watch folder export** - Optional setting that mirrors finalized
  sessions into a chosen folder (e.g. an iCloud Drive folder Cowork or
  Claude Code is configured to read). No integration plumbing, just a
  reliable file drop. Impact 4, Effort S, Horizon Now.
- **Lorre MCP server (local stdio)** - A small Model Context Protocol
  server that exposes `list_sessions`, `get_transcript`, `search_sessions`
  to local LLM clients. Lets Claude Code and similar tools pull transcripts
  on demand instead of relying on copy-paste. Impact 5, Effort M, Horizon
  Next.
- **Webhook export** - Generic `POST` of session JSON to a configured
  endpoint on completion, for users who want to wire Lorre into their own
  stack. Impact 3, Effort S, Horizon Next.
- **Rich Markdown styling options** - Optional front-matter, speaker color
  blocks, table-of-contents from bookmarks, timestamped headings, embedded
  audio links. Impact 2, Effort S, Horizon Next.
- **Anonymized export** - Replace speaker display names with generic
  labels (Speaker A, B) on export. Impact 2, Effort S, Horizon Next.

## Theme 9 - Privacy and data ownership

- **Privacy mode levels** - Today privacy mode is a single switch; split
  into "delete source audio", "delete stems", "redact PII on export" with
  granular toggles. Impact 3, Effort S, Horizon Now.
- **Retention policy** - Auto-delete sessions older than N days, with a
  per-folder override. Impact 3, Effort S, Horizon Next.
- **At-rest encryption** - Optional FileVault-style encryption of the
  Application Support directory, unlocked at app launch. Impact 4, Effort
  L, Horizon Later.
- **Export audit log** - Local log of when and where each session was
  exported, viewable in settings. Impact 2, Effort S, Horizon Later.

## Theme 10 - Companion surfaces

- **iOS / iPadOS companion** - Capture on iPhone, sync to Mac for
  processing. Even a minimal record-and-import-via-AirDrop flow would be
  useful. Impact 4, Effort XL, Horizon Later.
- **Apple Watch capture trigger** - Start / stop / bookmark from the
  watch. Impact 2, Effort M, Horizon Later.
- **Static web viewer for shared sessions** - Self-contained HTML + JSON
  bundle that renders the transcript with playback in any browser; usable
  for sharing without needing the desktop app. Impact 3, Effort M, Horizon
  Later.

## Theme 11 - Polish and platform

- **Onboarding wizard** - First-run guided setup: permissions, mic test,
  model download, optional calendar permission, auto-record opt-in.
  Impact 4, Effort S, Horizon Now.
- **In-app model manager** - Show installed FluidAudio components, sizes,
  versions; allow updates and clean reinstall. Builds on
  `ModelPreparationSnapshot`. Impact 3, Effort S, Horizon Next.
- **Multi-window** - Open a session in its own window for review while
  recording another. Impact 2, Effort M, Horizon Later.
- **Accessibility audit** - VoiceOver labels for waveform, transcript
  segments, recording controls; full keyboard navigation. Impact 3,
  Effort M, Horizon Now.
- **Crash and diagnostic capture (opt-in, local-only)** - Extend
  `LocalMetricsLogger` with a "Reveal diagnostics" command so users can
  share logs when filing issues. Impact 2, Effort S, Horizon Next.

## Theme 12 - Upstream (Jesse / jjscholtes) cherry-pick candidates

Our fork and upstream diverged at commit `f557dc5`. Our branch went deep on
the CoreAudio Process Tap rewrite, the Studio Sage design, and the 4-tab
Settings scene. Upstream went deep on dictation, call detection, and ASR
model options. The items below are the upstream features worth pulling back
into our fork, with integration notes specific to where our two codebases
differ.

**Status (branch `claude/fluidaudio-0.15-dutch-asr`, code complete, awaiting
GUI verification):**
- ✅ 12.0 Dutch default — done (batch language hint defaults to `.dutch`).
- ✅ 12.1 FluidAudio 0.15 + language selection — done (v3 multilingual with
  a real language hint; v2/Nemotron/Cohere modes not added — Cohere is an
  external dependency that conflicts with local-only privacy).
- ✅ 12.2 Call Watcher — done (detection engine + platform watcher +
  notification prompt + auto-record, opt-in).
- ✅ 12.3 Export templates — done (automatic Markdown export to a chosen
  folder with token filenames).
- ✅ 12.4 Global Dictation — done (hotkey → local transcribe → insert;
  status via banners instead of a dedicated overlay view).
- ✅ 12.5 Model settings in our Settings scene — language picker added to
  `SpeechModelsSettingsTab`; call/dictation/export controls in
  `GeneralSettingsTab` (not upstream's sidebar placement).

**Still needs runtime verification (cannot be tested headless):** FluidAudio
0.15 against our Process Tap audio, Dutch transcription quality, notification
permission for Call Watcher, and Accessibility permission + packaging
entitlements for Global Dictation text insertion.

**Shared seam to watch:** upstream made huge edits to `AppViewModel.swift`
(+1818 lines) and `Models.swift` (+456). Our versions of those files also
moved (Sage + Settings scene). The pure domain/value files cherry-pick
cleanly; anything touching `AppViewModel` wiring will need hand-merging,
not a literal `git cherry-pick`.

### Borrow vs rebuild map (file by file)

Verified against upstream `f557dc5..upstream/master`. Three buckets:
**Borrow** = copy almost verbatim; **Hand-merge** = additive but the file
also moved on our side, so port the new bits in by hand; **Rebuild** =
architecture diverged, use upstream only as a reference.

| Upstream file | Verdict | Why |
|---|---|---|
| `Core/Domain/CallDetection.swift` (474) | **Borrow** | Pure value types + detection logic, no UI/VM coupling. |
| `Tests/.../CallDetectionTests.swift` | **Borrow** | Comes with CallDetection; gives us coverage for free. |
| `Core/Domain/GlobalDictation.swift` (155) | **Borrow** | Pure config types + text formatter. |
| `Core/Export/AutomaticExportFileNameBuilder.swift` (310) | **Borrow** | Self-contained utility, zero coupling. |
| `Core/Support/CallWatcherPlatformServices.swift` (122) | **Borrow** | Uses `NSWorkspace` + `CGWindowList` + AVFoundation - **not** ScreenCaptureKit, so it does **not** conflict with our Process Tap rewrite. Verify against our process-enumeration world. |
| `Core/Support/CallPromptNotificationServices.swift` (204) | **Borrow** | `UserNotifications` behind a protocol; needs notif permission. |
| `Core/Support/GlobalDictationPlatformServices.swift` (760) | **Borrow** | Carbon hotkey + Accessibility insertion; heavy but self-contained behind protocols. |
| `Core/Domain/Protocols.swift` (+48) | **Hand-merge** | 4 new protocols (`CallWatcherService`, `CallPromptNotificationService`, `GlobalDictationHotKeyService`, `GlobalTextInsertionService`) - purely additive, append them. |
| `Core/Support/AppDependencies.swift` (+42) | **Hand-merge** | Additive: 4 new service fields + their live/disabled wiring in the factory. Clean to port. |
| `Core/Domain/Models.swift` (+456) | **Hand-merge** | New additive types (`BatchTranscriptionMode`, `BatchTranscriptionConfiguration`, `LiveTranscriptionPreset`, `AutomaticMarkdownExportConfiguration`, `CallWatcherConfiguration`, `GlobalDictationConfiguration`, `TranscriptAlternative`, `VocabularyBoostingEntry`). Our `Models.swift` also moved (schema work) - port type-by-type, keep `decodeIfPresent ?? default` and bump `schemaVersion` per our convention. |
| `Core/Support/AppSettingsStore.swift` (+181) | **Hand-merge** | New setter methods are additive; new `AppSettings` fields need a `schemaVersion` bump + fixture migration test (our rule). |
| `Core/Processing/FluidAudioAdapters.swift` (+572) | **Hand-merge** | Borrow the ASR model-selection logic; our capture pipeline (Process Tap CAF) feeds the same batch path, but validate buffer format + the live recognizer. |
| `Core/Support/FluidAudioLiveStreamingRecognizer.swift` (+312) | **Hand-merge** | Live preset/model handling; verify against our mic buffer feed. |
| `Package.swift` | **Hand-merge** | One-line FluidAudio `0.13.6 -> 0.15.0` bump; keep our `swift-tools-version: 6.3`, don't take upstream's. |
| `Features/Shell/AppViewModel.swift` (+1818) | **Rebuild** | Do **not** cherry-pick. Ours diverged hard (Sage + Settings + Process Tap). Re-wire the new feature methods (call watcher, dictation, ASR selection, export config) into our VM by hand, upstream as reference. |
| `Features/Shell/SessionShelfModelSettingsView.swift` | **Rebuild** | Upstream's sidebar placement conflicts with our Settings scene. Rebuild the controls inside our `SpeechModelsSettingsTab.swift`. |
| `Features/Shell/GlobalDictationOverlayView.swift` (242) | **Rebuild** | SwiftUI; restyle to Sage tokens. Upstream as visual reference. |
| `Features/Recorder/RecorderStageViews.swift`, `Features/Shell/SessionShelfSidebarView.swift`, `Features/Transcript/*` | **Rebuild** | Our Sage versions diverged; lift individual logic only, restyle. |

Net: the *brains* (detection, dictation, export-naming, ASR selection) are
borrowable; the *wiring and the chrome* (AppViewModel, the views, settings
placement) is where we rebuild because our fork's architecture moved.

### 12.0 - Default to Dutch (NL), not English (highest priority for this fork)

The most important item here and the smallest. Upstream's v3 model is
multilingual and already lists `nl` in `supportedLanguageCodes`
(`["en","fr","de","es","it","pt","nl","pl"]`), but the **default is
hardcoded to `"en"`** in several places (`languageHint = "en"`,
`languageCode = "en"`). Most of the primary user's meetings are in Dutch,
so an English default silently degrades the core transcript.

- Make NL the default batch language / language hint for this fork (or a
  first-run choice that we set to NL).
- Confirm the v3 multilingual path is the default ASR mode (not the
  English-only v2 path) so a Dutch meeting never lands on an English-only
  model by accident.
- Verify diarization + vocabulary boosting behave with NL.
- Impact 5, Effort S, Horizon Now. *This one is worth doing even before any
  other cherry-pick.*

### 12.1 - FluidAudio 0.15 + selectable ASR models

Upstream bumped FluidAudio `0.13.6 -> 0.15.0` and added selectable ASR
paths: `Parakeet v3 multilingual` (default), `Parakeet v2 English-only`,
`Parakeet + Cohere` (alternate draft), plus `Nemotron` streaming for the
live preview. Lives in `Package.swift`, `FluidAudioAdapters.swift` (+572),
`FluidAudioLiveStreamingRecognizer.swift`, and the model-mode types in
`Models.swift`.

- Pure quality win for the core task; this is the headline cherry-pick.
- Risk: 0.15 may interact with our Process Tap audio pipeline differently
  than upstream's ScreenCaptureKit path - validate the captured-buffer
  format and live-streaming recognizer against a real recording before
  trusting it.
- For our fork, prefer the multilingual v3 path (see 12.0); v2 English-only
  is a secondary option, not the default.
- The `Parakeet + Cohere` draft pulls in an external/hosted dependency -
  check whether it conflicts with our local-only privacy stance before
  enabling it (it may belong on the "out of scope" list).
- Impact 5, Effort M, Horizon Now.

### 12.2 - Call Watcher (folds into Theme 1)

Upstream's `CallDetection.swift` (474 lines, pure value types, with
`CallDetectionTests.swift`) plus `CallPromptNotificationServices.swift` and
`CallWatcherPlatformServices.swift` are a **working implementation of the
auto-record detection that our Theme 1 only specifies**. It detects that a
call/meeting has started (window-title hints, audio-activity summary,
capture-device usage, confidence bands) and prompts via a user notification.

- Treat this as the starting point for Theme 1 V1 rather than building the
  composite start-signal from scratch. Map upstream's `CallSignalSample` /
  `CallDetectionCandidate` / confidence bands onto our Armed/Recording state
  machines (Theme 1).
- The window-title / audio-activity detection pairs well with our Process
  Tap world (we already enumerate processes producing audio).
- Requires notification permission; gate behind a feature flag (per Theme 1
  mitigations) and a single `startRecording` entry point.
- Domain file is portable; the notification + platform services and the
  AppViewModel wiring need hand-merging.
- Impact 5, Effort M, Horizon Next. *Cross-reference Theme 1.*

### 12.3 - Export filename templates

`AutomaticExportFileNameBuilder.swift` (310 lines) is a self-contained
utility with zero coupling - templated export filenames (date, title,
speaker, etc.). Pairs naturally with our Theme 8 export work and the
watch-folder mirror.

- Easiest cherry-pick on the list; near-literal copy plus a settings hook.
- Impact 3, Effort S, Horizon Now.

### 12.4 - Global dictation

Upstream's system-wide dictation: speak via a global hotkey and insert the
text into whatever app is focused. `GlobalDictation.swift`,
`GlobalDictationPlatformServices.swift` (760 lines, Carbon hotkey +
Accessibility insertion), and `GlobalDictationOverlayView.swift` (242).

- This is a different product direction from "meeting transcription" - it
  turns Lorre into a system dictation tool. Decide whether that fits this
  fork's identity before investing.
- Heavy: needs Accessibility permission, a Carbon global hotkey service, and
  a pasteboard/paste-command insertion fallback. Highest effort, lowest fit.
- If pursued, it overlaps with Theme 5's "global hotkeys" item.
- Impact 2, Effort L, Horizon Later.

### 12.5 - Model settings, but in OUR Settings scene

Upstream keeps model settings inline in the sidebar
(`SessionShelfModelSettingsView.swift`). We deliberately moved settings into
the 4-tab Settings scene (`CMD+,`). So **do not** take upstream's sidebar
placement - instead, surface the new model controls (ASR mode picker,
batch-language picker incl. NL, live-engine picker) inside our existing
`SpeechModelsSettingsTab.swift`.

- This item is really "expose the 12.1 model options through our Settings UI"
  rather than a separate feature.
- The batch-language picker is where the 12.0 NL default becomes a
  user-visible control.
- Impact 3, Effort S, Horizon Now (depends on 12.1).

---

## Suggested release sequence

The roadmap is intentionally split so the AI-handoff plumbing ships before
the auto-record investment. Without a clean export the auto-record feature
records meetings into a workflow dead-end.

### Release N: Export hand-off (Theme 8)

Small, low-risk, unlocks the user's external AI workflow today.

1. `SessionManifest.schemaVersion` + fixture-based migration test suite
   (precondition for every additive schema change in later releases)
2. Rich JSON export envelope v1 with stable schema, placeholder
   `bookmarks` and `attendees` fields
3. "Copy as Markdown for Claude" command in the session export menu
4. Watch folder mirror: on session `.ready`, write JSON + structured
   Markdown to a user-chosen folder via security-scoped bookmark

### Release N+1: Auto-record Teams meetings via calendar (Theme 1 V1)

Scoped narrowly to scheduled Teams meetings as documented in Theme 1.

5. EventKit integration + Armed-state arming window
6. Teams composite start-detection signal
7. Activity-driven stop with cooling-down grace period
8. Per-calendar rules + persistent menu-bar status indicator
9. Pre-flight permission check at auto-start
10. Onboarding wizard covering the new auto-record opt-in (Theme 11)

### Release N+2: Capture polish and trust

11. Auto-identify enrolled speakers on new sessions (Theme 3)
12. Bookmarks during recording (Theme 4)
13. Full-text search across sessions (Theme 4)
14. Floating recording HUD + menu bar quick record (Theme 5)

Together these turn Lorre into a transcription utility that quietly
records the right meetings, produces a high-quality transcript, and
hands it off to whatever AI tool the user already uses to think.

---

## Regression risks and mitigations

Before picking up any item above, weigh it against the existing surface area.
The codebase has a few sensitive seams - persistence schemas with custom
`Codable`, a tight recording/processing pipeline, and a speaker-identity
layer that propagates into exports. The notes below call out where new work
is most likely to break existing behavior, and the mitigations to require
from the start.

### Highest risk

**Persistence schemas (`SessionManifest`, `TranscriptDocument`, `AppSettings`)**

Each type has a hand-written `init(from decoder:)` using `decodeIfPresent`
with defaults. Every new field added by items in Themes 2, 4, 8 and 9
(bookmarks, versions, attendees, per-folder vocab, privacy levels, schema
metadata) must follow that pattern or existing sessions stop loading.
`AppSettings.schemaVersion` is already at 2, `TranscriptDocument` at 1;
`SessionManifest` has no version field yet and should grow one before any
non-additive change.

- *Mitigation:* require a fixture-based migration test for every schema
  change. The existing `Tests/` target is a good home. Bump `schemaVersion`
  on non-additive edits and document the migration inline.

**Audio pipeline and live preview**

- Auto-record (Theme 1) starts a session while Zoom / Teams may hold the
  mic exclusively or apply their own voice processing. The recording can
  succeed but capture silence or distorted audio. A pre-flight check helps
  but adds latency that may clip the first few words.
- Noise suppression (Theme 6) changes the signal that reaches Parakeet,
  which was trained on relatively clean audio. Aggressive
  `AVAudioUnitVoiceProcessing` can *lower* transcription quality.
- Pause / resume (Theme 5) has no native `AVAudioFile` support. Splicing
  stems or buffer-flushing risks audio / transcript timestamp drift and
  can break the `FluidAudioLiveStreamingRecognizer` state machine.
- Loudness normalization on export is one-way and can make system-audio
  unexpectedly loud.

- *Mitigations:* keep noise suppression opt-in with an A/B accuracy check
  on a fixture corpus before defaulting it on; treat pause/resume as a
  stop-and-start-new-stem internally to avoid state-machine changes; gate
  every auto-record path through the same pre-flight as manual recording.

**Recording lifecycle in auto-record (Theme 1)**

- Calendar signal, process detection, and manual start can fire together
  and spawn duplicate sessions or overwrite a just-started one.
- Smart-stop on "call ended" can truncate audio if the user keeps talking
  after the conferencing app exits the call state.
- Polling `NSWorkspace.runningApplications` or audio routing costs battery
  and can keep mic / screen-recording permissions hot even when not
  recording.
- Screen recording permission for system audio is a separate gate; an
  auto-start without that check produces a recording with no system audio
  and the user only notices afterwards.

- *Mitigations:* a single `startRecording` entry point that debounces
  signals; a grace period on smart-stop with an audio-activity check; a
  permission preflight before the auto-record toast even appears.

**Speaker auto-match (Theme 3)**

Wrong auto-assignment to a `KnownSpeaker` propagates straight into
exports, the watch folder, and the MCP server, so downstream tools get
mislabeled data silently.

- *Mitigations:* require a confirm step above a defined similarity
  threshold; log every automatic decision (reuse `LocalMetricsLogger`)
  so wrong matches are traceable; make profile merge / split reversible
  by retaining the pre-merge embeddings.

**Export schema lock-in (Theme 8)**

Once Claude Code, Cowork, or the MCP server depend on the JSON shape,
breaking changes hurt. Watch-folder writes that are not atomic let
downstream tools read half-written files.

- *Mitigations:* ship the JSON export with an explicit `schemaVersion`
  and a short documented schema from day one; commit to additive-only
  changes within a major version; route every export through
  `AtomicFileWriter` (it already exists for session/transcript writes);
  bind the MCP server to localhost only and keep it read-only in v1.

### Medium risk

**Full-text search (Theme 4)**

An index that drifts out of sync with edits causes "I searched and Maria
isn't there but she is" bugs. CoreSpotlight integration leaks transcript
content into system search.

- *Mitigations:* rebuild-on-launch path plus incremental updates on every
  transcript edit; keep CoreSpotlight indexing opt-in (sqlite FTS5 by
  default) to avoid surprising users who chose Lorre for privacy.

**Floating HUD and menu bar (Theme 5)**

- `NSPanel` over full-screen conferencing apps needs the right activation
  policy or it steals focus from Zoom controls.
- Menu bar quick-record plus the main-window record button creates two
  paths into `AppViewModel.startRecording` and risks duplicate sessions.

- *Mitigations:* one shared command target in `AppViewModel`; explicit UI
  tests for HUD focus behavior against full-screen apps.

**Privacy mode levels (Theme 9)**

Splitting the current single bool into multiple toggles requires a
migration that maps the old state to the most conservative new
combination. Retention auto-delete is destructive and easy to get wrong
on sessions with missing `recordedAt`.

- *Mitigations:* default migration biases toward retention (keep more,
  delete less); auto-delete moves files to a local trash with a 30-day
  reversal window before unlinking; unit tests on edge cases
  (missing dates, in-progress sessions, sessions with no transcript).

### Lower risk

**Translation (Theme 7)**

Apple Translation requires macOS 14.4+; the project minimum is macOS 14.0.

- *Mitigation:* gate the feature with `if #available` and surface a clear
  "requires macOS 14.4" note in settings.

**Find / replace and diarization touch-ups (Theme 2)**

Splitting segments without updating `tokenTimings` produces wrong
timestamps in SRT / VTT and breaks tap-to-play on a word.

- *Mitigation:* every split / merge operation must rebuild
  `tokenTimings` consistently; cover with unit tests that round-trip a
  session through edit and export.

### Cross-cutting practices to adopt up front

- **Migration test suite.** A fixture per schema version, decoded by the
  current code, asserted to match expected values. Adds a hard wall
  against silent data loss.
- **`AtomicFileWriter` everywhere.** Not just `transcript.json` and
  `session.json` - also Markdown export, JSON export, watch-folder
  mirror, and any new on-disk artifact.
- **Feature flags in `AppSettings` for risky features** (auto-record,
  noise suppression, CoreSpotlight indexing). Default off, so a
  regression on a new path cannot harm existing users.
- **One `startRecording` code path.** Auto-record, menu bar, hotkey, URL
  scheme, and the main window all funnel through the same function
  with the same preflight, debounce, and permission checks.
- **Snapshot tests on the JSON export schema.** Any accidental field
  rename or removal turns red before it ships.
- **Confirmation thresholds and audit logs for automatic decisions**
  (speaker auto-match, auto-start, auto-stop). Reuse
  `LocalMetricsLogger` so the user can inspect what Lorre decided on
  their behalf.
