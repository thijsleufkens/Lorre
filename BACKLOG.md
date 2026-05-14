# Lorre Feature Backlog

A working backlog of features for upcoming releases of this Lorre fork. The
guiding principle: keep the local-first, on-device privacy story intact while
closing the gap with Granola-style meeting workflows. Anything that touches an
LLM should be pluggable so users can pick between a local model (MLX / Ollama /
Apple Intelligence) and a hosted provider.

Each item lists rough **Impact** (1-5), **Effort** (S/M/L/XL) and a **Horizon**
(Now / Next / Later). Items are not yet ordered or committed to a release.

---

## Theme 1 - AI notes and summarization

Granola's standout feature is taking rough live notes from the user and
rewriting them into clean, structured notes using the transcript as ground
truth. Lorre already stores a `notes` field on `SessionManifest`; this theme
turns it into a first-class workspace.

- **AI summary panel** - Generate a structured summary (overview, key points,
  decisions, action items, open questions) from the finalized transcript.
  Streamed into a side panel, regeneratable, with provenance links back to
  transcript segments. Impact 5, Effort M, Horizon Now.
- **Augmented notes ("Granola mode")** - User types rough bullets during the
  call; on stop, Lorre rewrites them with transcript context as the source of
  truth, preserving the user's voice and section order. Impact 5, Effort L,
  Horizon Now.
- **Note templates** - Built-in and user-defined templates (1:1, customer
  discovery, standup, interview, lecture, retro, sales call). Each template is
  a prompt + heading skeleton. Impact 4, Effort S, Horizon Now.
- **Action item extraction with owners and due dates** - Surface assignable
  action items in a dedicated section; allow one-click export to Things /
  Reminders / Linear / Todoist via URL schemes. Impact 4, Effort M, Horizon
  Next.
- **Ask Lorre chat** - Side-pane RAG chat over the active transcript
  ("What did Maria commit to?"). Streams answers with citation chips that
  scroll the transcript view to the cited segment. Impact 4, Effort M, Horizon
  Next.
- **Pluggable LLM provider** - Provider abstraction with adapters for local
  MLX, Ollama, Apple Intelligence (Foundation Models framework), Claude,
  OpenAI, and any OpenAI-compatible endpoint. Per-provider API keys stored in
  Keychain. Impact 5, Effort M, Horizon Now (prerequisite for the items
  above).
- **Local-only mode badge** - When a session is processed with only local
  models the UI shows an "Air-gapped" badge; switching to a cloud provider
  prompts an explicit confirm. Impact 3, Effort S, Horizon Now.

## Theme 2 - Meeting context and calendar integration

- **EventKit calendar awareness** - With user permission, list upcoming
  meetings in the sidebar, pre-fill session title, attendees, and meeting
  link, and offer a "Start recording" button per event. Impact 5, Effort M,
  Horizon Now.
- **Auto-join detection** - Detect when Zoom / Google Meet / Teams / FaceTime
  starts and offer a non-modal "Record this meeting?" toast. Impact 4, Effort
  M, Horizon Next.
- **Attendee directory** - Build a lightweight contacts store from calendar
  attendees so known speakers can be linked to email addresses. Useful for
  auto-suggesting speaker labels when an enrolled voice matches an invitee.
  Impact 3, Effort M, Horizon Next.
- **Pre-meeting briefing** - One-pager generated from prior sessions with the
  same attendees: last decisions, open action items, recent topics. Impact 4,
  Effort M, Horizon Later.

## Theme 3 - Transcript quality and editing

The current `TranscriptSegment` model and review UI is solid; this theme
makes it pleasant to clean up and trust.

- **Confidence-based review queue** - Highlight low-confidence segments
  (uses `confidence` already on `TranscriptSegment`) and offer a "Review next
  uncertain segment" command. Impact 4, Effort S, Horizon Now.
- **Diarization touch-ups** - Drag a divider to split a segment or merge
  consecutive segments; bulk reassign a contiguous range to a speaker.
  Impact 4, Effort M, Horizon Now.
- **Word-level timing edits** - Use the `tokenTimings` already produced by the
  ASR pipeline to support tap-to-play on a specific word and word-level
  redaction. Impact 3, Effort M, Horizon Next.
- **PII / redaction tool** - Detect and one-click redact emails, phone
  numbers, card numbers, addresses. Redacted spans persist in the transcript
  and exports. Impact 4, Effort M, Horizon Next.
- **Versioned transcripts** - Keep a lightweight history of edits per session
  with diff view and revert. Impact 3, Effort M, Horizon Later.
- **Custom vocabulary per session/folder** - Extend the existing
  `VocabularyBoostingConfiguration` to support per-folder glossaries and
  shared team glossaries (JSON import/export). Impact 3, Effort S, Horizon
  Now.

## Theme 4 - Speaker identity

Lorre already ships speaker enrollment via FluidAudio; this theme makes the
identity layer cross-session and trustworthy.

- **Auto-identify enrolled speakers on new sessions** - Match diarized
  speakers to the `KnownSpeakerStore` at the end of processing, with a
  confirm step for borderline matches. Impact 5, Effort M, Horizon Now.
- **Speaker fingerprint management UI** - Browse enrolled speakers, listen to
  reference clips, merge two profiles, re-enroll with a new sample. Impact
  3, Effort S, Horizon Now.
- **Talk-time analytics** - Per-speaker speaking time, interruption count,
  longest monologue, talk ratio. Surfaced on the session detail view and in
  exports. Impact 3, Effort S, Horizon Next.
- **Cross-session insights** - "Show all sessions where Maria spoke" and
  "Quotes from Maria in the last 30 days". Impact 3, Effort M, Horizon
  Later.

## Theme 5 - Organization, search and library

- **Full-text search across all sessions** - Index transcripts and notes
  with on-device search (CoreSpotlight or a small sqlite FTS5 store). Filter
  by speaker, date range, folder, language. Impact 5, Effort M, Horizon Now.
- **Smart folders / saved searches** - Folders defined by a query rather
  than manual assignment (e.g. all sessions tagged `customer-call` in the
  last quarter). Builds on the existing `SessionFolder` model. Impact 3,
  Effort M, Horizon Next.
- **Tags and colors** - Free-form tags on sessions, with autocomplete from
  prior tags. Impact 2, Effort S, Horizon Next.
- **Bookmarks and highlights** - Star a timestamp during or after a meeting
  with an optional note; bookmarks aggregate into a per-session "Highlights"
  view and into exports. Impact 4, Effort S, Horizon Now.
- **Auto-chapters** - Detect topic shifts in long sessions and propose
  chapter markers (uses the LLM provider). Impact 3, Effort M, Horizon
  Later.

## Theme 6 - Capture experience

- **Floating recording HUD** - Compact always-on-top widget with mic level,
  elapsed time, pause, stop, and a "Capture this moment" bookmark button.
  Survives full-screen apps. Impact 4, Effort M, Horizon Now.
- **Menu bar quick record** - One-click record from the menu bar without
  opening the main window; uses the last-used source. Impact 4, Effort S,
  Horizon Now.
- **Pause and resume** - Pause/resume mid-recording with a visible gap in
  the resulting waveform and transcript. Impact 4, Effort M, Horizon Now.
- **Pre-flight check** - Before recording starts, run a 2-second check on
  the mic and system audio routes and warn if the level is too low or
  permissions are missing. Impact 3, Effort S, Horizon Now.
- **Global hotkeys** - Configurable shortcuts for start/stop, pause,
  bookmark moment, toggle live preview. Impact 3, Effort S, Horizon Next.
- **URL scheme** - `lorre://record?source=mic&template=1on1` for Shortcuts,
  Raycast, Stream Deck. Impact 2, Effort S, Horizon Next.
- **Scheduled recordings** - Start a recording at a fixed time, or X minutes
  before a calendar event. Impact 2, Effort M, Horizon Later.

## Theme 7 - Audio pipeline

- **Noise suppression pre-pass** - Optional pre-processing stage (e.g.
  Apple's `AVAudioUnitVoiceProcessing` or a small CoreML denoiser) before
  ASR for noisy environments. Impact 3, Effort M, Horizon Next.
- **Loudness normalization** - Apply EBU R128 loudness target on playback
  and on export to keep mixed mic+system audio comfortable. Impact 2,
  Effort S, Horizon Next.
- **Background processing queue UI** - Show a queue and per-job progress
  for batch imports; `ProcessingCoordinator` already emits the events, the
  UI just needs surfacing. Impact 3, Effort S, Horizon Now.
- **Resumable processing** - If the app quits during transcription, resume
  from the last persisted chunk rather than restarting. Impact 3, Effort M,
  Horizon Later.
- **Speaker-aware live preview** - Today the live preview shows an active
  speaker hint; extend it to show a rolling per-speaker color stripe so the
  user can see who is talking in real time. Impact 3, Effort S, Horizon
  Now.

## Theme 8 - Translation and multilingual

Parakeet covers 25 European languages; the UX should follow.

- **On-the-fly translation pane** - Show the transcript translated to the
  user's preferred language alongside the source, with a toggle. Local
  translation via Apple's Translation framework when available, LLM
  fallback otherwise. Impact 4, Effort M, Horizon Next.
- **Translated exports** - Export markdown / SRT / VTT in a chosen target
  language. Impact 3, Effort S, Horizon Next.
- **Language switching mid-session** - Detect language changes (e.g. NL ->
  EN halfway through a call) and label sections accordingly. Impact 2,
  Effort M, Horizon Later.

## Theme 9 - Export, sharing and integrations

- **Subtitle export (SRT / VTT)** - Straightforward addition next to the
  existing `ExportFormat` enum. Impact 3, Effort S, Horizon Now.
- **Rich Markdown styling** - Optional front-matter, speaker color blocks,
  table-of-contents from chapters, embedded audio links. Impact 2, Effort
  S, Horizon Next.
- **Share to Notion / Linear / Slack** - Use each tool's public API to push
  a clean note. Notion: page with summary + action items; Linear: one
  issue per action item; Slack: shared digest in a channel. Impact 4,
  Effort M, Horizon Next.
- **Email digest** - One-click "send recap email" using the system mail
  composer with templated body. Impact 3, Effort S, Horizon Next.
- **Webhook export** - Generic `POST` of session JSON to a configured
  endpoint on completion, for users who want to wire Lorre into their own
  stack. Impact 2, Effort S, Horizon Next.

## Theme 10 - Privacy and data ownership

- **At-rest encryption** - Optional file-vault style encryption of the
  Application Support directory, unlocked at app launch. Impact 4, Effort
  L, Horizon Later.
- **Retention policy** - Auto-delete sessions older than N days, with a
  per-folder override. Impact 3, Effort S, Horizon Next.
- **Privacy mode levels** - Today privacy mode is a single switch; split
  into "delete source audio", "delete stems", "redact PII on export" with
  granular toggles. Impact 3, Effort S, Horizon Now.
- **Export anonymized transcript** - Replace speaker display names with
  generic labels (Speaker A, B) on export. Impact 2, Effort S, Horizon
  Next.

## Theme 11 - Companion surfaces

- **iOS / iPadOS companion** - Capture on iPhone, sync to Mac for
  processing. Even a minimal record-and-import-via-AirDrop flow would be
  useful. Impact 4, Effort XL, Horizon Later.
- **Apple Watch capture trigger** - Start / stop / bookmark a session from
  the watch. Impact 2, Effort M, Horizon Later.
- **Web viewer for shared sessions** - Static export bundle (HTML + JSON)
  that renders the transcript with playback in any browser; usable for
  sharing without needing the desktop app. Impact 3, Effort M, Horizon
  Later.

## Theme 12 - Polish and platform

- **Onboarding wizard** - First-run guided setup: permissions, mic test,
  model download, LLM provider choice, optional calendar permission.
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

## Theme 13 - Experimental / stretch

- **Real-time meeting coach** - During a call, surface gentle nudges
  ("You've been talking for 4 minutes", "Maria hasn't spoken yet"). Pure
  local. Impact 3, Effort L, Horizon Later.
- **Semantic timeline scrubbing** - Drag the playhead and see the topic
  under the cursor as a tooltip. Impact 2, Effort M, Horizon Later.
- **Plugin system** - Allow third-party prompts and exporters as signed
  bundles users can install. Impact 3, Effort XL, Horizon Later.
- **Voice command palette** - "Hey Lorre, bookmark this" while recording.
  Local wake word, no cloud. Impact 2, Effort L, Horizon Later.

---

## Suggested next release (v0.x+1)

A small, coherent slice that delivers the Granola-style core without
over-committing:

1. Pluggable LLM provider (Theme 1)
2. AI summary panel with action items (Theme 1)
3. Note templates (Theme 1)
4. Augmented notes / "Granola mode" (Theme 1)
5. EventKit calendar sidebar (Theme 2)
6. Full-text search across sessions (Theme 5)
7. Bookmarks during recording (Theme 5)
8. Floating recording HUD + menu bar quick record (Theme 6)
9. Onboarding wizard (Theme 12)

Together these turn Lorre from a strong local transcriber into a complete
local meeting workspace, while keeping the privacy story unique among
Granola-class tools.
