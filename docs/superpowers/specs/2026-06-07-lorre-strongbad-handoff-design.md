# Lorre → Strongbad handoff (JSON + Markdown envelope)

**Date:** 2026-06-07
**Status:** Design approved, ready for implementation plan
**Scope:** Lorre-side only (this repo). The Strongbad consumers are separate specs.

## Context

Thijs runs Lorre locally on macOS to capture meetings and produce clean,
speaker-labelled Dutch transcripts (Parakeet v3, local, privacy-first). He
also runs **Strongbad**, a self-hosted VPS (isolated LXC container, Tesla A2
GPU, host-Qwen LLM, an existing faster-whisper → LinkedIn "Acquired Taste"
pipeline, Postgram knowledge base, and a heartbeat/backup/cron convention).

The goal is to let Strongbad consume Lorre's finished transcripts for two
downstream workflows:

1. **Ingest → Postgram**: a Strongbad cron turns each new transcript into a
   meeting entity in Postgram, linked to people.
2. **Meeting → LinkedIn**: feed transcripts into the existing Acquired Taste
   generator to draft posts in Thijs's voice.

Both consumers need the same thing first: a reliable, machine-readable
**handoff** from Lorre. This spec covers only that handoff. Lorre's product
philosophy is preserved — it produces clean source material and hands it off
to external tools the user controls; it does not summarise or run LLMs itself.

## Decisions (from brainstorming)

- **Transport: cloud-synced folder (option A).** Lorre drops files into a
  cloud-synced folder (Dropbox/iCloud); Strongbad pulls them via an
  rclone/rsync cron. No network code in Lorre; offline-tolerant.
- **Payload: JSON + Markdown (option C).** JSON is the machine contract;
  Markdown is the human-readable copy and input for the LinkedIn generator.
- **Scope: all sessions (option A).** When automatic export is enabled, every
  finished session is written. One global toggle, no per-session/folder
  gating. (The VPS container is isolated, so per-session privacy gating is
  YAGNI for now.)
- **Implementation: extend the existing auto-export (approach 1).** Reuse the
  `automaticMarkdownExport` config, folder picker, `.ready` hook, filename
  builder, and `MarkdownExportService` — add a JSON sidecar alongside the MD.

## Architecture & data flow

On session `.ready` (after `ProcessingCoordinator.process` succeeds and the
transcript is saved), if automatic export is enabled and a folder is set,
`AppViewModel.performAutomaticMarkdownExportIfNeeded` writes **two** files to
the configured cloud-synced folder:

- `<templated-name>.md` — human-readable (existing behaviour)
- `<templated-name>.json` — the machine contract (new)

Lorre only drops files. Cloud sync handles transport; the Strongbad cron
handles ingest timing. Nothing in Lorre talks to Strongbad directly.

## The JSON envelope (the contract)

Reuse `MarkdownExportService.renderJSON` unchanged. Its shape is:

```json
{
  "session": { /* full SessionManifest */ },
  "transcript": { /* full TranscriptDocument */ },
  "exportedAt": "2026-06-07T09:30:00Z"
}
```

Both `SessionManifest` and `TranscriptDocument` are `schemaVersion`-ed, so the
envelope is forward-compatible. What Strongbad relies on:

- `session.id` (UUID) — the **dedup / upsert key**. A re-exported (edited)
  session overwrites the same files; the cron upserts into Postgram by `id`.
- `session.title`, `session.createdAt` / `recordedAt`, `session.durationSeconds`,
  `session.recordingSource` — meeting metadata.
- `transcript.segments[]` — `startMs`, `endMs`, `speakerId`, `text`,
  `confidence` (the body text).
- `transcript.speakers[]` — `displayName` for enrolled speakers (people-linking
  in Postgram).
- `transcript.languageHint` — the meeting language (see below).
- `transcript.sourceEngine` — provenance.

No schema change is required; the envelope is already complete.

## languageHint coupling

Today `TranscriptDocument.languageHint` is left at its static default `"en"`
because `TranscriptAssembler.assemble` never sets it. This makes the envelope's
language field misleading. Fix it by threading the chosen batch language down:

- `AppViewModel.launchProcessing` already knows `batchTranscriptionLanguage`.
  Pass its language code into `ProcessingCoordinator.process(...)`.
- `ProcessingCoordinator` forwards it to `TranscriptAssembler.assemble(...)`,
  which sets `TranscriptDocument(languageHint: ...)`.
- Mapping: a concrete language → its code (e.g. `"nl"`). `.automatic` → `nil`
  (the detected language is not reliably exposed by FluidAudio, so we record
  "unknown" rather than a wrong guess). `nil` encodes as absent/null.

This is additive (a new optional parameter with a default), so existing call
sites and tests are unaffected.

## Lorre-side changes

1. **`AppViewModel.performAutomaticMarkdownExportIfNeeded`** — after the MD
   write, also write the JSON sidecar:
   `exporter.export(session:transcript:format:.json, destinationURL:<base>.json)`,
   where `<base>` is the MD filename with its extension swapped to `.json`.
   If either write fails, surface which one failed in the existing banner
   (no silent half-write).
2. **`TranscriptAssembler.assemble`** — add a `languageHint: String?` parameter
   and pass it to the `TranscriptDocument` initializer.
3. **`ProcessingCoordinator.process`** — add a `languageCode: String?` parameter
   and forward it to the assembler.
4. **`AppViewModel.launchProcessing`** — pass the configured language code
   (concrete code, or `nil` for `.automatic`).
5. **Settings copy** — relabel the "Automatic export" section to make clear it
   writes both Markdown and JSON. No new toggle, no `AppSettings` schema change.

## Filename & idempotency

- Filenames come from the existing `AutomaticExportFileNameBuilder` template
  (human-friendly: `{date}-{smart_title}`). The MD and JSON share the base name
  with different extensions.
- Filenames may collide across sessions (same date + title). That is fine: the
  machine dedup key is `session.id` **inside** the JSON, not the filename.
  Strongbad upserts by `id`. (A future option is to append a short id suffix to
  the template; out of scope here.)

## Error handling

- Reuse the existing failure banner from `performAutomaticMarkdownExportIfNeeded`.
- Write MD and JSON independently; report the specific file that failed so a
  partial write is visible rather than silent.

## Testing

- Extend the export tests with an assertion that the JSON envelope decodes and
  contains `session.id` and non-empty `transcript.segments` for a session with
  segments.
- Add a test that `TranscriptAssembler.assemble` stamps the provided
  `languageHint` (concrete code set; `nil` when automatic).
- `AutomaticExportFileNameBuilder` is already covered.

## Out of scope (separate specs, Strongbad-side)

- **#1 Ingest → Postgram**: rclone/rsync cron pulling the cloud folder,
  parsing the JSON envelope, upserting meeting entities + people links into
  Postgram, following the Strongbad heartbeat/backup/new-project convention.
- **#2 Meeting → LinkedIn**: feeding the transcript text into the existing
  Acquired Taste generator to draft posts in Thijs's voice.

Both consume the JSON envelope defined here. Building them happens on/against
Strongbad, not in this repo.
