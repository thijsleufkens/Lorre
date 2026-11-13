# Lorre as a meeting-outcomes tool (product direction)

**Date:** 2026-11-11
**Status:** Superseded by `2026-11-13-lorre-product-spec.md` (rebuild instead of extending the current app).
**Scope:** Product direction and architecture for Lorre as a whole. Individual phases get their own specs.

## Context

Lorre today records a conversation, transcribes it locally (Parakeet TDT 0.6B v3 via FluidAudio), labels
speakers, and exports Markdown + a JSON envelope. Downstream, Thijs's Strongbad pipeline (lorre-ingest)
turns that envelope into Postgram meetings and LinkedIn drafts.

The question that started this spec was whether to swap the ASR model (Desert Ant's Voz was tested on
2026-11-11). The answer was: the model is not the bottleneck. The problems seen in practice sit in the
pipeline around it:

- **A crash loses the recording.** Stems are written to `$TMPDIR/Lorre/recording-tmp/` and a session only
  exists after Stop. On 2026-10-08 the call watcher crashed mid-call; the session was recovered by hand from
  the temp folder before macOS cleaned it up.
- **The best signal is thrown away.** In mic+system mode Lorre has two separate tracks (mic = the user,
  system = everyone else), but `ProcessingCoordinator` transcribes and diarizes only the mono mix
  (`session.audioFileName`). The stems are only referenced to delete them. Diarization then has to guess
  what was known for free.
- **No context.** The meeting is almost always in the calendar (participants, organisation, subject), but
  nothing uses it: not for speaker names, vocabulary, title, or conversation type. ASR language is one global setting (default: automatic), not chosen per meeting.
- **Weak metadata.** Titles like "audio" or `druk-allemaal-dingetjes-ben-die-wat-meer-beetje`.
- **Same weights, different output.** Voz runs the identical Parakeet weights, yet its transcript differed
  noticeably from Lorre's (chunking and decoding). Pipeline choices matter at least as much as the model.

## Direction

A meeting is work: open points get discussed, information gets shared, decisions get made, actions get
handed out. Lorre's job becomes: **turn a conversation into an approved record of what it produced**, in a
form the user's own agent can pick up.

This deliberately reverses one principle from the 2026-06-07 handoff spec ("Lorre does not summarise or
run LLMs itself"). Lorre now proposes outcomes with small local models. It still does not act on them.

Target users, beyond Thijs:

- **the coach** (independent leadership coach): intakes for assignments, and network conversations without a
  direct assignment that yield a hook to call back after some time.
- Other independents and small teams with the same pattern.

Out of scope: content generation (LinkedIn posts, product ideas). It is niche and personal; the existing
Acquired pipeline can keep consuming Lorre's output.

## What a conversation yields (the outcome model)

| Kind | Meaning | Maps to (GTD, for Thijs) |
|---|---|---|
| Decision | Something agreed, including "we will not do X" | — |
| My action | Something the user committed to | `next` |
| Their commitment | Something someone else committed to | `waiting` |
| Open point | Raised, not resolved | — |
| Information | A fact shared that matters later | — |
| Follow-up hook | When and about what to get back in touch | `scheduled` |
| Person note | What was learned about a participant (role, organisation, what is going on) | — |

Every proposed item carries:

- **Evidence**: segment ids and a time range, so the reviewer can read and hear the source moment.
- **Owner** (for actions and commitments) and **due** (if stated).
- **Status**: `proposed` → `approved` / `rejected`. Editing is not a status: an approved item carries an
  `edited` flag when the reviewer changed the proposal (useful for measuring model quality later).
  Rejected items stay inside Lorre and are not part of the record.

Conversation types shape extraction: a work meeting, an intake (need, scope, budget, next step) and a
network conversation (person, what is going on, hook) need different emphasis. The type comes from the
calendar where possible and is correctable in review.

## The chain

| Stage | Today | Target |
|---|---|---|
| 1. Capture | Stems in `$TMPDIR`; session created at Stop | Session folder created at Start; stems streamed into it; recovery on launch. Never lose a recording. |
| 2. Transcribe + speakers | Mono mix → ASR → diarization | Online call (mic+system): per track, mic track = the user, system track diarized for the others. In-person (mic only): everyone is on the mic, so diarize the mic track as today. Calendar participants as name candidates and vocabulary in both cases. |
| 3. Propose | Nothing | Small local model extracts the outcome model, with evidence. |
| 4. Review | Transcript editing only | Review UI: approve / edit / reject each item; fix speaker names, title, type. |
| 5. Record | JSON envelope (session + transcript), exported automatically | The envelope keeps exporting automatically, unchanged. After approval a versioned **meeting record** is added: approved outcomes + session + transcript. |
| 6. Access | Cloud folder + CLI `transcribe` | File contract first; CLI (`list`, `show`); MCP server on top. |

The in-person case matters because it is the coach's main scenario (intakes on location). There the
"track per person" advantage does not exist until a second device is added (phase 4), so owner attribution
depends on diarization quality plus correction in review. In mic+system mode without headphones the other
party also bleeds into the mic track; voice processing (AEC) suppresses most of it, to be checked in
phase 1.

## Boundary (non-goals)

- Lorre does not track actions after approval. It is not a task manager.
- Lorre does not integrate with destinations (Postgram, task tools, CRMs, Positive Projects). That is the
  job of the user's agent, reading the record.
- No live or realtime features during the call.

## Design principles (partly borrowed from Detail)

Detail (Paul Veugen; "Capture The Conversation") shares Lorre's front half: capture, sync, speakers,
transcript. Its output is an edited video; Lorre's is a meeting record. Borrowed ideas:

1. **One tap, then the human corrects.** Like Detail's Auto Edit: one action yields a complete proposal; the
   UI is built for correcting, not for building from scratch.
2. **A track per person.** Detail syncs a second device or a browser guest. Separate tracks make speaker
   attribution nearly free, which matters because ownership of actions depends on who said it. Lorre's
   mic/system split is the first step; a second device (e.g. a phone near the other party at an on-site
   intake) is a later one.
3. **Prepare → record → deliver.** Detail starts before recording (teleprompter, script). Lorre's
   equivalent: before a meeting, show the open points, commitments and hook from the last conversation
   with these people. Outcomes of meeting 1 become the agenda of meeting 2. (This can live in the user's
   agent via the MCP rather than in Lorre itself; to decide.)
4. **Evidence with every proposal.** Like Clips, every item links to its moment (transcript excerpt +
   audio). Reviewing an item should take seconds, not a reread of the transcript.
5. **Product polish.** If others use it, the bar is a consumer app, not "works for Thijs with a CLI".

## Output contract

The record is the product boundary. Sketch (to be refined in the phase spec):

```json
{
  "schemaVersion": 1,
  "recordId": "…",
  "recordVersion": 1,
  "session": {
    "id": "…", "title": "…", "type": "intake", "recordedAt": "…",
    "participants": [ { "id": "p1", "name": "Thijs", "isUser": true }, { "id": "p2", "name": "…" } ]
  },
  "outcomes": [
    {
      "id": "…",
      "kind": "myAction",
      "text": "Send proposal for the data-quality scan",
      "ownerId": "p1",
      "due": "2026-11-18",
      "edited": false,
      "evidence": { "segmentIds": [ "…" ], "startMs": 812000, "endMs": 828000 }
    }
  ],
  "transcript": { … },
  "approvedAt": "…"
}
```

Rules:

- **Two outputs, two triggers.** The existing envelope (session + transcript) keeps exporting automatically
  after processing, exactly as today, so lorre-ingest and the Acquired consumer keep working and a
  conversation that is never reviewed still arrives downstream. The meeting record is written only after
  approval. Proposals never leave Lorre.
- A record contains only approved outcomes, so items carry no status field.
- `recordId` is stable per session; `recordVersion` increments each time the record is re-approved after a
  change. `recordId` + `recordVersion` make consumption idempotent (lorre-ingest keys on `session.id`
  today).
- Owners reference a participant id, not a free-text name, so a corrected speaker name updates everywhere.
- **Processed state is per consumer.** A consumer identifies itself with a name (e.g. `lorre-ingest`) and
  marks `recordId` + `recordVersion` as processed via CLI/MCP. Lorre stores this in its own application
  support folder, not in the record file: the record stays immutable and the cloud folder stays read-only
  for consumers. "List new records" is always relative to the asking consumer. Consumers that only read
  files keep their own bookkeeping, as lorre-ingest does now.
- Access is layered: **files** (works with any tool, easy to test) → **CLI** → **MCP server** (thin layer:
  list new approved records, get a record, mark processed).

## Small local models

This is the assumption everything rests on. Extracting decisions and owned actions from a 45-minute Dutch
conversation is hard for a small model. Candidates:

- **Apple Foundation Models** (on-device, free). Requires macOS 26 and Apple Silicon with Apple
  Intelligence enabled, on every user's Mac (Lorre targets macOS 15; the coach's hardware to check); small
  context window, so the transcript must be processed in chunks and merged.
- **Open 4–8B model via MLX.** More control, a few GB of download, quality to be measured.

Review absorbs errors, but a model that misses half the actions makes review useless (missed items are
invisible). Recall matters more than precision.

**Validation experiment (do first):** hand-annotate 2–3 real conversations (e.g. 2026-10-08, 2026-06-11)
with the outcome model; run candidate models; measure recall of actions with the correct owner, and of
decisions.

- **Input: transcripts with hand-corrected speaker labels.** Otherwise a wrong owner cannot be told apart
  from a wrong speaker label, and the experiment would measure diarization instead of the model. (A second
  run on the uncorrected transcript shows how much phase 1 has to deliver.)
- **Thresholds, to be agreed before running.** Proposal: ≥ 80% recall on actions with the correct owner,
  and ≥ 50% precision over all proposed items. Recall weighs more, but a model that buries the real items
  under noise makes review just as useless.
- Two or three conversations is a go/no-go signal, not a benchmark. Include at least one in-person
  recording if available.

## Privacy and consent

- Recording other people requires their knowledge; the product should make that easy (e.g. a consent
  reminder at Start), especially for the coach's coaching and intake conversations.
- Everything stays on the device by default; this is a selling point and constrains the model choice.
- Audio retention: keep Privacy Mode (delete audio after processing), but the evidence-with-audio principle
  needs audio until review is done. Delete after approval is the likely default.
- GDPR: coaching and intake conversations can contain sensitive personal data about the other party. The
  user is the controller; local-only processing keeps this simple, but once others use Lorre the product
  needs a clear statement of what is stored where and for how long, and the cloud export folder becomes
  the user's explicit choice rather than a default.

## Distribution (decided 2026-11-11)

No paid Apple Developer account, since there is no revenue model.

- Sign with a self-signed code-signing certificate instead of ad-hoc, so the designated requirement is
  tied to the certificate rather than the binary hash.
- The app is not notarized, so each new user approves it once in Gatekeeper ("Open Anyway").
- Updates via Sparkle with its own EdDSA keys.
- Accepted trade-offs: no App Store, a one-time Gatekeeper step per user, and exposure to future Apple
  tightening for non-notarized apps. Fine for the coach and a technical audience, not for a broad one.

## Open questions

1. **Model runtime:** Apple Foundation Models (macOS 26 bump) vs MLX open model vs both. Decided by the
   validation experiment.
2. **the coach as a real user:** confirm with her that she will use it and what she needs (onboarding, no
   CLI required, which Mac and macOS she has).
3. **TCC with a self-signed certificate:** verify in phase 0 that microphone and audio-capture grants
   survive a rebuild when the signing identity stays the same.
4. **Calendar access:** EventKit (macOS Calendar, including synced Outlook/Google accounts) vs a
   per-provider connector. EventKit keeps it local.
5. **Preparation loop:** in Lorre, or left to the user's agent via the MCP?
6. **Multi-device capture:** worth it, and when? It is the only route to a track per person for in-person
   conversations.
7. **MCP transport:** stdio server inside the existing binary (like the CLI routing) is the obvious first
   choice; verify the Swift MCP SDK fits.
8. **Consumers and the record:** the envelope stays (see Output contract), so no migration is forced. Open
   is whether lorre-ingest should later also read the record to pick up approved actions and hooks.

## Suggested phasing

| Phase | Content | Why this order |
|---|---|---|
| 0 | Crash-safe recording + self-signed signing identity + the model validation experiment | Losing recordings is unacceptable; stable TCC grants remove the per-build permission reset; the experiment decides if the direction is viable. |
| 1 | Per-track processing + calendar context (names, vocabulary, title, type) | Correct speakers are a precondition for owned actions; also improves today's transcripts. |
| 2 | Extraction + review UI + meeting record | The core of the new product. |
| 3 | CLI `list`/`show` + MCP server | Opens it to any agent. |
| 4 | Preparation loop, multi-device capture, distribution for other users | Builds on a working core. |
