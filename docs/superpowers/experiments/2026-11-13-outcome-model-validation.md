# Outcome-model validation, first run

**Date:** 2026-11-13
**Status:** First signal only. One conversation, one prompt, annotation not yet reviewed by Thijs.
**Question:** can a small local model propose the outcomes of a Dutch conversation well enough that
review is fast and nothing important is missed?

## Setup

- **Conversation:** the 8 Oct 2026 online network conversation, 29 minutes, 382 segments, Parakeet v3
  transcript with its normal recognition errors. Names are left out of this document.
- **Speakers:** not taken from diarization. Per segment, energy in the microphone track was compared with
  energy in the system-audio track.
- **Reference (annotated by Claude, to be checked by Thijs):** 3 actions/commitments with an owner,
  1 decision, plus softer items (1 optional action, 1 open point, 1 hook, several facts).
  1. Commitment (other): pass Thijs's name to two contacts, who will get in touch.
  2. Action (Thijs): introduce the other person to a contact at an agency.
  3. Commitment (other): approach that agency himself.
  4. Decision: Thijs does not join the event next Friday.
- **Models:** `gemma4:e4b` and `qwen3.5:9b` via Ollama on an M1 with 16 GB, temperature 0, JSON output.
  Both were already on the machine and are 7–8 months old. Apple Foundation Models could not be run:
  the system reported `modelNotReady`.
- **Variants:** whole transcript in one request with speakers from the tracks; whole transcript with the
  original diarization labels; six 5-minute chunks with speakers from the tracks.
- **Thresholds proposed beforehand:** ≥ 80% recall on actions with the correct owner, ≥ 50% precision.

## Finding 1: diarization on the mix failed completely; the tracks did not

| Method | Result |
|---|---|
| Diarization on the mono mix (current pipeline) | 371 of 382 segments labelled as one speaker; the other 11 "unknown" |
| Energy per track | 311 segments (81%) attributed to one side; 71 (19%) ambiguous, mostly segments that span a speaker change |

The ambiguous segments exist because segment boundaries come from ASR on the mix. Transcribing each track
separately removes them.

### Addendum: Who (Desert Ant) on the same mix

Who 0.3.4 (SDK 4.3.0, beta) was run on the same mono mix, with the per-track energy as reference
(100 ms frames where exactly one track is clearly active).

| Method on the mono mix | Speakers found | Frames with the right speaker | Segments with the right speaker |
|---|---|---|---|
| FluidAudio VBx as configured in Lorre today | 1 | n/a | n/a |
| Who | 2 | 91.3% (7.0% wrong speaker, 1.8% missed) | 298 of 311 (96%) |

Processing took 41 s for 29 minutes on an M1. Limits of this comparison: the reference is an energy
heuristic, not a hand annotation; FluidAudio ran with the old clustering threshold that upstream has since
corrected, so the fair comparison is still to be made; and an online call is Who's best case (both voices
close to a microphone). An in-person recording has not been tested.

**Simulated room recording.** No in-person recording was available, so the two tracks were remixed to
imitate one: artificial reverb, a low-pass filter, pink background noise, and the other speaker 10 dB
quieter (variant A), or both speakers reverberant with a 4 dB difference (variant B).

| Mix | Speakers found | Frames with the right person | Note |
|---|---|---|---|
| Original mix | 2 | 91.3% | |
| Variant A (other speaker far away) | 10 | 93.7% | Eight extra "speakers" of 2–6 s each, plus one of 40 s |
| Variant B (both in the room) | 4 | 93.1% | One person split in two (107 s under a second label) |

The two main voices stay well separated, but Who starts inventing extra speakers. The percentages count a
split-off label as correct when it belongs to the right person, so they flatter the result; the usable
signal is the speaker count. Merging small speakers (the SDK has a minimum-share filter) and a
speaker-count hint from the calendar would address most of this. A simulation is not a room: real
recordings have overlap, movement and a real room response, so this still needs a real in-person test.

## Finding 2: without correct speakers the proposals are wrong, not just incomplete

With the original labels both models swapped the two people throughout: the user was described as the
photographer, the other person's commitment became the user's action, and all timestamps were invented.
With speakers from the tracks these role swaps largely disappeared. Correct speakers are a precondition,
not an improvement.

## Finding 3: no tested model meets the thresholds

Scores against the four reference items. "Found" means the content is there; "correct" means kind and
owner are also right.

| Run | Time | Items | Actions found (of 3) | Actions correct (of 3) | Decision (of 1) | Noise |
|---|---|---|---|---|---|---|
| gemma4:e4b, whole | 101 s | 8 | 2 | 1 | 0 | Low; nothing invented |
| qwen3.5:9b, whole | 176 s | 14 | 2 | 0 (owner left empty) | 0 | One invented decision, one fact on the wrong person |
| gemma4:e4b, chunks | 409 s | 69 | 3 | 1 | 0 | High: 51 facts; about 11 of 18 non-fact items are quotes that are not outcomes |
| qwen3.5:9b, chunks | 399 s | 42 | 3 | 1 | 0 (found, labelled open point) | Medium: about 7 of 19 non-fact items are not outcomes; a name garbled |
| Either model, original labels | 122–129 s | 10–18 | 1 | 0–1 | 0 | Roles swapped throughout |

Reading:

- **One request over the whole transcript misses items.** Both models found two of three and skipped the
  decision.
- **Chunks find everything but bury it.** All three actions appear, with far too many items and frequent
  wrong kinds and owners. The chunked gemma run returned quotes instead of summaries.
- **Speed is a problem on this hardware.** Seven minutes of processing for a 29-minute call does not fit
  "review within two minutes after the conversation" unless it runs during processing anyway (ASR and
  diarization also take time) or on a faster Mac.

## What this does and does not show

- It shows that the naive approach (one prompt, an older 4–9B model) is not good enough, and that the
  product must not depend on the proposal being complete.
- It does not show that small models cannot do it. Untested: a two-step pipeline (find candidates per
  chunk, then one consolidation request that merges, drops non-outcomes and assigns kind and owner),
  current models, Apple Foundation Models, a cleaner transcript (per-track ASR, Parakeet Ultra), and
  type-specific prompts.
- The sample is far too small for percentages: three actions and one decision. A network conversation
  is also the hardest type; commitments are phrased loosely ("dan zal ik je link doorsturen").

## Consequences for the product spec

1. Build review-by-hand before proposals (already the build order). The record and the agent handoff
   deliver value without the model.
2. Per-track speakers move ahead of proposals, since proposals are wrong without them.
3. The proposal step gets the two-step design, and "add a missed outcome from the transcript" is a core
   interaction, not an edge case.

## Next steps

1. Thijs checks the four reference items and adds what is missing.
2. Annotate a second conversation of a different type (a work meeting with real actions).
3. Re-run with the two-step pipeline, a current model and Apple Foundation Models once it is available.
4. Decide on thresholds with the larger set.

Scripts, transcripts and raw outputs are kept outside the repository because they contain the
conversation itself.

## Addendum 2026-11-14: per-track speakers and the two-step proposer

Same conversation, same reference, `gemma4:e4b`, now through the built pipeline (`Lorre process` on a copy
of the data, then `Lorre propose --dry-run`).

**Speakers.** Per-track processing gave 464 segments: 192 from the microphone track (the user) and 272
from the system track (one other speaker). Processing 29 minutes took 1 min 51 s on the M1. The mono-mix
path had labelled everything as one speaker.

**Proposals, three runs of the two-step proposer:**

| Run | Items | Actions found (of 3) | Actions correct (of 3) | Decision (of 1) | Time |
|---|---|---|---|---|---|
| 1, as built | 25 | 3 | 1 | 0 | 20 min (machine also building) |
| 2, with owner fallbacks and name rules | 7 | 2 | 2 | 0 | 15 min |
| 3, plus a guard against lumped consolidation | 20 | 2 | 2 | 0 | 16 min |

- Run 1: the two commitments of the other person lost their owner because the model translated the
  placeholder name ("Spreker 1" became "Speaker 1"). Fixed in the matcher, plus two rules: my action is
  always the user's, and a commitment falls back to the only other person.
- Run 2: the consolidation step poured every candidate of a kind into one item (seven items, each a
  paragraph). The proposer now distrusts a consolidation in which one item merges more than three
  candidates and falls back to the step-1 candidates.
- Run 3: owners are right, sentences are readable, noise is far below the 42–69 items of the naive chunked
  runs. One commitment and the decision are still missed, and identical input does not give identical
  output between runs.

**Reading.** The two-step design and correct speakers remove the worst failures (swapped roles, quotes,
dozens of facts), but this model still misses one in three actions and the decision, and takes about a
quarter of an hour on this hardware. The thresholds (80% recall with the right owner) are not met.
Proposals therefore stay off by default: the setting is empty and review by hand is the normal path.
`Lorre eval` exists to repeat this measurement when a better model is available. The placeholder name
"Ik" for the user reads badly in generated sentences ("Ik's naam"); recordings made after the first-run
screen carry the user's real name.
