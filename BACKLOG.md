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

## Theme 1 - Auto-detect and auto-record meetings (headline)

The single biggest workflow win: never forget to start recording. Lorre
should know a meeting is happening and offer (or just start) a recording.

- **Conferencing app detection** - Detect when Zoom, Google Meet (in Chrome /
  Safari / Arc), Microsoft Teams, FaceTime, Webex, and Slack huddles enter an
  active call state. Use a combination of running processes, window titles,
  and audio output device routing. Impact 5, Effort M, Horizon Now.
- **Auto-record toast** - When a call starts, show a non-modal toast with
  "Record this meeting" (default action), "Not this one", and "Always for
  this app". Respects the user's last choice for ~10 minutes to avoid
  re-prompting after a quick disconnect. Impact 5, Effort S, Horizon Now.
- **Silent auto-start mode** - Opt-in mode that just starts the recording
  without prompting, with a clear menu-bar indicator. For users who want
  zero friction. Impact 4, Effort S, Horizon Now.
- **Calendar-driven recording** - With EventKit permission, infer that a
  meeting is starting from the user's calendar and combine the signal with
  conferencing app detection so titles, attendees, and meeting links are
  pre-filled on the new session. Impact 5, Effort M, Horizon Now.
- **Smart stop** - Stop recording when the conferencing app exits the active
  call state, after a configurable grace period. Confirm before stopping if
  audio is still being detected (e.g. continued discussion in person after
  the call ends). Impact 4, Effort S, Horizon Now.
- **Per-app rules** - "Always record Zoom", "Never record FaceTime",
  "Ask for Teams". Stored in settings, editable from the auto-record
  toast. Impact 4, Effort S, Horizon Now.
- **Pre-flight check at auto-start** - Run a 1-second mic/system-audio check
  before committing to the recording so a misrouted output device is caught
  before the user has talked for ten minutes. Impact 4, Effort S, Horizon
  Now.

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

---

## Suggested next release

A coherent slice that lands the new product focus:

1. Conferencing app detection + auto-record toast (Theme 1)
2. Smart stop + per-app rules (Theme 1)
3. Calendar-driven session metadata (Theme 1)
4. Auto-identify enrolled speakers on new sessions (Theme 3)
5. Bookmarks during recording (Theme 4)
6. Full-text search across sessions (Theme 4)
7. Floating recording HUD + menu bar quick record (Theme 5)
8. Rich JSON export + "Copy as Markdown for Claude" + watch folder (Theme 8)
9. Onboarding wizard covering the new auto-record opt-in (Theme 11)

Together these turn Lorre into a transcription utility that quietly records
the right meetings, produces a high-quality transcript, and hands it off to
whatever AI tool the user already uses to think.

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
