# Lorre: from conversation to approved record (product spec)

**Date:** 2026-11-13
**Status:** Draft for review by Thijs. Supersedes `2026-11-11-lorre-meeting-outcomes-direction.md`.
**Decided:** rebuild the product around the kept audio engine; one output (the record); macOS 26 minimum;
no paid Apple Developer account; no backward-compatibility constraints (the current app has no users).

## 1. The goal

> Within two minutes after a conversation ends, an approved record of what it produced is available to
> the user's own agent, and no conversation is ever lost.

A conversation is work: open points are discussed, information is shared, decisions are made, actions are
handed out. Lorre turns that into a record. Lorre proposes; the user approves; the user's agent acts.
Lorre never acts on outcomes itself and is not a task manager.

Three measurable promises:

| Promise | Measure |
|---|---|
| Nothing is lost | A crash, force-quit or power loss at any moment leaves a recoverable conversation. |
| Review is fast | Median review time under two minutes for a 30-minute conversation. |
| The record can be trusted | Every outcome links to the moment it was said; nothing unapproved leaves Lorre as an outcome. |

## 2. Users and scenarios

| Scenario | Who | Capture | What matters most |
|---|---|---|---|
| Online work meeting | Thijs | mic + system audio | Actions with the right owner, decisions |
| Online network conversation | Thijs | mic + system audio | Introductions promised both ways, the hook to call back, who is who |
| In-person intake | the coach | microphone only | Need, scope, budget, next step; no CLI, no setup |
| In-person network conversation | the coach | microphone only | Person note and hook |

the coach is the test for "useful for others": if she cannot install it, record, review and get the result
to wherever she works without help, the product is not done.

## 3. Product principles

1. **Outcomes first, transcript as evidence.** The transcript is never the main screen. It is what you
   see when you doubt an outcome.
2. **One action, then correct.** After a conversation there is one complete proposal. The UI is built for
   correcting it, not for building it.
3. **Evidence with everything.** Every outcome plays its own moment with one key.
4. **Missed items must be cheap to add.** The model will miss things, and misses are invisible. Adding an
   outcome from a transcript selection takes one gesture.
5. **Recording is invisible.** Starting is one click or automatic; it never needs the main window.
6. **Local by default.** Audio, transcript and proposals stay on the Mac. The only thing that leaves is the
   record, to a folder the user chose.
7. **Models are replaceable parts.** Speech, speaker and language models improve every few months. No
   model is part of the design: each sits behind a protocol, is chosen by measurement, and can be swapped
   without touching the product.
8. **Lorre remembers, the agent acts.** Lorre keeps people and past outcomes so it can show what is open
   with someone. It does not track completion, send reminders or write to other systems.

## 4. Information architecture

Three places and one always-available control:

| Place | Answers | Contains |
|---|---|---|
| **Today** (start screen) | "What needs me?" | Conversations waiting for review; the next calendar meetings with what is open with those people |
| **Conversations** | "What was said when?" | All conversations, searchable across transcript and outcomes |
| **People** | "What is going on with this person?" | Per person: conversations, open commitments both ways, hook, notes |
| **Recorder** (menu bar + small floating panel) | "Record this" | Start/stop, elapsed time, level, source |

Settings stay a separate window (General / Capture / Models / Export & agents / About).

### 4.1 Today

```
┌──────────────────────────────────────────────────────────────────────┐
│ Lorre          Today   Conversations   People              ● Record  │
├──────────────────────────────────────────────────────────────────────┤
│ TO REVIEW                                                            │
│ ┌──────────────────────────────────────────────────────────────────┐ │
│ │ Call with R. (new contact)         today 10:00 · 29 min          │ │
│ │ 3 actions · 1 decision · 5 other                      Review  →  │ │
│ └──────────────────────────────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────────────────────────────┐ │
│ │ Margin review with S.              yesterday · 47 min            │ │
│ │ 6 actions · 2 decisions · 4 other                     Review  →  │ │
│ └──────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│ COMING UP                                                            │
│ 14:00  S. (client) — weekly                                          │
│        Open with S.:   2 of yours, 1 of his · last spoke 6 Nov       │
│ 16:30  Intake — new contact                                          │
│        No history                                                    │
└──────────────────────────────────────────────────────────────────────┘
```

- Empty state: "Nothing to review" plus the next meeting. No dashboard filler.
- A conversation that is still processing appears here with progress, not in a separate view.
- "Coming up" needs calendar access; without it the section is hidden, not broken.

### 4.2 Review (the core screen)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ←  Call with R. (new contact) ✎      Network conversation ▾          │
│    Thijs · R. ✎                      8 Oct 10:00 · 29 min            │
├───────────────────────────────────┬──────────────────────────────────┤
│ ACTIONS                           │ EVIDENCE                 ▶ 21:26 │
│ ▸ ○ R. passes my name to J. and   │ R.   vind je het goed als ik     │
│     P.                    R. ▾    │      jouw naam doorgeef aan      │
│   ○ Introduce R. to T.            │      J. en P. …                  │
│     (agency)              Thijs ▾ │ R.   zal ik jou link al          │
│   ○ R. approaches the agency      │      doorsturen en dan nemen     │
│     himself               R. ▾    │      zij wel contact             │
│ DECISIONS                         │ Thijs  Jazeker.                  │
│   ○ Not joining the event next    │                                  │
│     Friday                        │ ──────────────────────────────── │
│ OPEN POINTS                       │ Full transcript ▾                │
│   ○ One-on-one in person, no date │                                  │
│ INFORMATION  (5)             ▸    │                                  │
│ HOOK                              │                                  │
│   ○ R. is curious about next steps│                                  │
├───────────────────────────────────┴──────────────────────────────────┤
│ A approve · X reject · E edit · Space play · N new    Approve all ⌘↩ │
└──────────────────────────────────────────────────────────────────────┘
```

Behaviour:

- **Left: outcomes grouped by kind**, actions first. Information is collapsed by default (most items,
  least urgency).
- **Right: the evidence for the selected outcome**: the transcript excerpt around it, with audio. `Space`
  plays the moment. "Full transcript" expands the excerpt into the whole transcript at that position.
- **Keyboard first:** `↑↓` move, `A` approve, `X` reject, `E` edit text, `O` change owner, `K` change kind,
  `Space` play, `N` new outcome, `⌘↩` approve everything still proposed and finish.
- **Adding a missed item:** select text in the transcript → a small popover offers the kinds → the outcome
  is created with that selection as evidence and the speaker as owner.
- **Owner** is a participant, shown as a menu. Changing a participant's name updates every outcome.
- **Header corrections:** title, conversation type and participant names are editable in place; two
  participants can be merged when the diarizer split one person. Changing
  the type offers to re-run the proposal (types emphasise different kinds).
- **Finishing** writes the record, shows where it went, and returns to Today. Until then nothing is
  exported as an outcome.
- **Low-confidence markers:** an outcome whose owner came from an ambiguous speaker segment shows a small
  "check owner" hint instead of pretending certainty.

### 4.3 Person

```
┌──────────────────────────────────────────────────────────────────────┐
│ ←  S. (client)                     Machine builder · controller   ✎  │
├──────────────────────────────────────────────────────────────────────┤
│ OPEN                                                                 │
│  Yours   Send margin analysis per product group        from 6 Nov    │
│  Yours   Check ERP export for Q3                       from 30 Oct   │
│  His     Deliver cost-price table                      from 6 Nov    │
│ HOOK     Call again after the year-end close (January)               │
│ NOTES    Moved from finance to operations in September               │
│ CONVERSATIONS                                                        │
│  6 Nov  Weekly · 47 min     30 Oct  Weekly · 38 min    …             │
└──────────────────────────────────────────────────────────────────────┘
```

- "Open" lists approved actions and commitments from past records that were not superseded. The user can
  mark one "no longer open" (a local flag for this view only; Lorre does not sync task status).
- People are created from participants at approval. Merging two people is supported (same person, two
  spellings).

### 4.4 Recorder

- A menu-bar item is always present. Click: start with the last-used source. The floating panel shows
  elapsed time, input levels per track and Stop.
- **Call detection** (kept from the current app): when a call app starts using the microphone, a
  notification offers to record. Never starts silently.
- **Consent reminder** at start, one line, dismissible per conversation type ("Tell the other person this
  is being recorded").
- **Calendar match** at start: if a meeting is in progress, its title and participants are attached.
- After Stop the panel shows "Processing…" and then a notification: "Your conversation is ready to
  review", which opens the review screen directly.

### 4.5 First run (the coach's path)

1. Open the app (one-time "Open Anyway" in System Settings; the download page shows it with a screenshot).
2. Three steps, each skippable later: microphone permission → model download with size and progress →
   choose where records go (a folder; default `~/Documents/Lorre`).
3. Optional: calendar access, system-audio permission (only asked the first time an online call is
   recorded).
4. Lands on Today with a "Record a test conversation" card.

No CLI, no agent and no account are needed to get value: the approved record is also written as a
readable Markdown file next to the JSON.

## 5. Conversation lifecycle

```
recording → processing → proposed → approved ⇄ changed
     ↘ interrupted (recoverable at next launch)
```

| State | On disk | Exported |
|---|---|---|
| recording | Conversation row + folder created at Start; tracks streamed into the folder | nothing |
| interrupted | Same; detected at launch, offered for processing | nothing |
| processing | Tracks, then transcript | nothing |
| proposed | Transcript + proposed outcomes | Record with `status: "draft"`: session, participants, transcript, **no outcomes** |
| approved | Approved outcomes | Record with `status: "approved"`, outcomes included, `recordVersion` 1 |
| changed | Edited after approval | Same record, `recordVersion` + 1 |

The draft record exists so that an unreviewed conversation still reaches the user's agent as a transcript
(what lorre-ingest gets today). Proposals are never exported: an agent must not act on something no human
confirmed.

## 6. Domain model

| Entity | Key fields | Notes |
|---|---|---|
| Conversation | id, title, type, startedAt, duration, state, calendarEventId | Replaces "session" |
| Track | conversationId, kind (mic / system / device), file | One per captured source |
| Person | id, name, organisation, role, notes | Persists across conversations |
| Participant | conversationId, personId?, name, isUser, trackKind? | Links a speaker in one conversation to a Person |
| Segment | id, conversationId, participantId, startMs, endMs, text, confidence | Word timings kept |
| Outcome | id, conversationId, kind, text, ownerParticipantId?, due?, status, edited, evidence (segment ids + range), source (model / user) | Kinds below |
| Record | conversationId, version, status, approvedAt, path | What was exported |
| ConsumerCursor | consumerName, recordId, recordVersion, processedAt | Per-consumer processed state |

Outcome kinds: `decision`, `myAction`, `theirCommitment`, `openPoint`, `information`, `followUpHook`,
`personNote`. Conversation types: `workMeeting`, `intake`, `network`, `other`; a type sets which kinds the
proposal emphasises and how they are ordered in review.

**Storage:** SQLite (GRDB) for everything above, with FTS5 for search across transcript and outcomes;
audio in a folder per conversation. JSON-per-session folders are dropped: "what is open with this person"
is a query, not a file scan. Existing sessions are imported once (title, transcript, audio).

## 7. Architecture

| Module | Content | Origin |
|---|---|---|
| `LorreCapture` | Process Tap system audio, mic with voice processing, timeline-aligned track writers, crash-safe streaming into the conversation folder | Kept from the current app (the May–June findings), plus recovery |
| `LorreSpeech` | ASR, diarization, vocabulary, per-track speaker attribution, processing queue | Kept; rebased on upstream's engine work (section 8) |
| `LorreCore` | Domain model, SQLite store, outcome proposal, record writer | New |
| `LorreApp` | SwiftUI app: Today, Review, People, Recorder, Settings, onboarding | New. One observable model per screen; no app-wide view model |
| `lorre` | CLI and MCP server (stdio) inside the same binary | CLI routing kept; commands new |

Rules: `LorreCore` has no UI imports and is what the CLI and MCP use. Each screen owns its state. The
Sage design tokens are kept; the components are rebuilt for the new screens.

### 7.1 Model flexibility

Three model roles, each behind a protocol in `LorreSpeech` / `LorreCore`:

| Role | Protocol | Candidates today |
|---|---|---|
| Speech to text | `Transcriber` | Parakeet v3, Parakeet Ultra (FluidAudio); Voz |
| Who spoke when | `Diarizer` | FluidAudio VBx, Who |
| Outcomes from transcript | `OutcomeProposer` | Apple Foundation Models, an MLX model, the user's agent via MCP |

Rules that keep swapping cheap:

- **Protocols speak Lorre's types.** Segments, turns and outcomes are Lorre's own; no SDK type crosses
  the protocol boundary. An adapter per engine is the only code that knows the SDK.
- **Provenance is stored.** Every transcript, speaker assignment and proposal records engine, model
  version and settings. A conversation can be re-processed with a newer model; the earlier version is
  kept, and manual corrections and approved outcomes are never overwritten.
- **A fixed evaluation set decides.** A small set of annotated conversations (reference speakers and
  reference outcomes) lives outside the repository, with a command (`lorre eval`) that runs any engine
  against it and reports speaker accuracy, word errors on a vocabulary list, and outcome recall and
  precision. A new model becomes the default only when it wins there. The first run of this is in
  section 10; review corrections from daily use grow the set.
- **Selection is configuration.** The default per role is a setting with a sensible preset; users are
  not asked to pick models. Advanced settings expose the choice.
- **Downloads are managed in one place.** Size shown beforehand, resumable, removable.

### 7.2 Speakers

Measured on the 8 Oct call (see section 10): diarization on the mono mix labelled the whole conversation
as one speaker. Comparing energy in the two tracks attributed 81% of segments directly; the remaining
19% were segments that span a speaker change.

Consequences:

- **Online (mic + system):** transcribe each track separately. The mic track is the user. The system
  track is diarized only if the calendar says there is more than one other participant. Segment
  boundaries come from the tracks, so a segment never spans two people.
- **In-person (mic only):** diarize the mic track, with upstream's improved per-word assignment.
  Attribution is weaker here; review shows the "check owner" hint more often.
- **Speaker-count hint:** the number of calendar participants is passed to the diarizer, and speakers
  with a very small share are merged into their neighbour. In a simulated room recording Who split two
  people into four to ten labels; both measures target that.
- **Merging speakers in review:** "this is the same person" joins two labels and updates every segment
  and owner. Required for in-person conversations.
- **Diarization engine:** stays behind a protocol. On the 8 Oct mix, Desert Ant's Who (beta) separated the
  two speakers with 91% of frames correct where Lorre's current diarization found one speaker. Before
  choosing, compare Who with upstream's corrected FluidAudio settings on that mix and on an in-person
  recording (milestone 4). Who sends licence pings (no audio or text); that needs a line in the privacy
  statement if it ships.
- **Names:** calendar participants are the candidates; saved voice profiles confirm them where available.

### 7.3 Outcome proposal

- A `OutcomeProposer` protocol with one implementation per runtime, chosen by the validation in
  section 10. The app must work without one (review then starts empty and outcomes are added by hand),
  so the review screen can be built and used before the model question is closed.
- Pipeline: transcript in overlapping windows → proposals per window → merge duplicates → attach evidence
  by matching the stated time to segments → validate owner against participants.
- Inputs besides the transcript: conversation type, participant names, the user's name, and open items
  with these people from earlier records (so "as discussed last time" can be linked).

### 7.4 Record and access

Record sketch:

```json
{
  "schemaVersion": 1,
  "recordId": "…", "recordVersion": 1, "status": "approved",
  "conversation": {
    "id": "…", "title": "…", "type": "network", "startedAt": "…", "durationSeconds": 1741,
    "participants": [ { "id": "p1", "name": "Thijs", "isUser": true }, { "id": "p2", "name": "…", "personId": "…" } ]
  },
  "outcomes": [
    { "id": "…", "kind": "theirCommitment", "text": "…", "ownerId": "p2", "due": null, "edited": false,
      "evidence": { "segmentIds": ["…"], "startMs": 1286000, "endMs": 1343000 } }
  ],
  "transcript": { "segments": [ { "id": "…", "participantId": "p2", "startMs": 0, "endMs": 0, "text": "…" } ] },
  "approvedAt": "…"
}
```

- Written as `<date> <title>.json` plus a readable `.md` into the export folder.
- **CLI:** `lorre list [--new --consumer NAME]`, `lorre show ID`, `lorre mark-processed ID --consumer NAME`,
  `lorre person NAME`, `lorre transcribe FILE` (kept).
- **MCP (stdio):** `list_records`, `get_record`, `mark_processed`, `get_person` (open items and hook, for
  preparation by the user's agent).
- Processed state is per consumer and stored in Lorre's database, never in the record file.

## 8. What to take from upstream (jjscholtes/Lorre 0.5)

Upstream moved on by 41 commits since the fork, in a different direction: it hardens the transcription
workspace (reliability, newer models, dictation). It contains nothing about outcomes, people or agents,
so it does not change the product design. It does contain engine work that this spec needs:

| Upstream change | Value here | Take? |
|---|---|---|
| Recording recovery and interrupted-processing detection | The "nothing is lost" promise; we planned to build this | Yes, as the starting point |
| Diarization accuracy (VBx threshold 0.6, per-word speaker assignment, zero-vote re-embed) | Owner attribution, above all for in-person conversations | Yes |
| FluidAudio 0.17.7 and Parakeet Ultra (reported multilingual WER 14.8% → 11.7%) | Better Dutch at the same speed; to confirm on our own audio | Yes, measure first |
| Vocabulary corrections kept through segment building | Custom vocabulary already exists in Lorre, but corrected words were lost when segments were rebuilt. With this fix, names from the calendar and People can feed the vocabulary automatically | Yes |
| Re-transcribe with version history | Existing conversations benefit from a better model without losing edits | Yes |
| Processing queue (one job at a time) | Needed once conversations queue up for processing | Yes |
| Apple Lossless storage after processing | Smaller archive; we keep audio until review is done | Yes |
| Transcript search | Becomes FTS5 search in the new store | Idea only |
| Echo cancellation with system audio as reference (noted as exploration) | Would remove the other party bleeding into the mic track | Later, experiment |
| Dutch live preview, global dictation, extra live models | Outside the goal | No |

Caveat: both sides changed the recorder and the processing code heavily (41 vs 114 commits), so this is a
port of specific pieces, not a merge. Upstream targets macOS 14 and does not have our Process Tap capture.

## 9. Distribution, privacy, platform

- **macOS 26 minimum, Apple Silicon.**
- **Signing:** self-signed code-signing certificate, not notarized; one-time "Open Anyway" per user;
  updates via Sparkle with our own EdDSA keys. To verify first: permissions survive an update when the
  signing identity is unchanged.
- **Privacy:** everything local; the export folder is an explicit choice. Audio is kept until approval
  and then deleted by default (setting: keep). Consent reminder at Start.
- **GDPR:** the user is the controller. The app states plainly what is stored where and for how long.

## 10. Model validation

First run on 2026-11-13, one conversation; details in
`docs/superpowers/experiments/2026-11-13-outcome-model-validation.md`.

- **Not passed.** Two older local models (4–9B) found two of three actions when given the whole
  transcript, and all three when given 5-minute chunks, but then with 40–70 items and frequent wrong
  kinds and owners. The one decision was missed or mislabelled in every run.
- **Speakers are a precondition.** With the diarization labels both models swapped the two people.
- **Not yet tested:** a two-step pipeline (candidates per chunk, then one consolidation request), current
  models, Apple Foundation Models (not ready on the test machine), a second conversation.

The spec therefore does not depend on the proposal being complete: review works by hand (milestone 3),
speakers come before proposals (milestone 4), and the proposal step (milestone 5) uses the two-step
design. If no local model passes by milestone 5, the fallback is to let the user's own agent propose
outcomes through the MCP (`propose_outcomes` writing proposals into Lorre for review), which keeps the
approval step and the record unchanged.

## 11. Build order

Each milestone ends in something usable; done-criteria are part of the milestone.

| # | Milestone | Done when |
|---|---|---|
| 1 | **Foundation**: package split, SQLite store, domain model, import of existing sessions, self-signed build | Existing conversations are listed from the database; a rebuild keeps permissions |
| 2 | **Capture that cannot lose**: conversation created at Start, tracks streamed into its folder, recovery at launch, menu-bar recorder | Killing the app mid-recording loses nothing; verified with injected failures |
| 3 | **Review by hand**: Today + Review screens with outcomes added manually, evidence playback, record export (JSON + Markdown) | Thijs reviews a real call end to end and his agent reads the record |
| 4 | **Speakers**: per-track transcription, upstream diarization and vocabulary fixes, calendar names, `lorre eval` with the first reference set | The 8 Oct call gets the right owner on every action without correction; diarizer and transcriber defaults are chosen by `lorre eval` |
| 5 | **Proposals**: the chosen model behind `OutcomeProposer`, type-specific prompts, merge and evidence linking | Meets the thresholds on the annotated set; median review under two minutes |
| 6 | **People and preparation**: People screen, "Coming up" with open items | Before a call, Today shows what is open with that person |
| 7 | **Agents**: CLI and MCP server, consumer cursors | An agent lists new records, reads one, marks it processed |
| 8 | **For others**: onboarding, Sparkle updates, download page, the coach trial | the coach installs and completes a conversation without help |

Review by hand (3) comes before proposals (5) on purpose: it delivers the record and the agent handoff
without depending on the model, and it produces the corrected data the model is measured against.

## 12. Open questions

1. Which model runtime (section 10).
2. the coach: will she use it, on which Mac and macOS, and where does her record need to go?
3. Calendar: EventKit is assumed (local, covers synced Outlook and Google accounts). Confirm it sees
   Thijs's work calendar.
4. In-person speaker quality is unmeasured on a real recording (only simulated). Proceeding without it;
   test as soon as one real in-person recording exists.
5. A second device as an extra track for in-person conversations: after milestone 8, if in-person
   attribution proves too weak.
6. lorre-ingest: adapt it to the new record (draft and approved) at milestone 3.
