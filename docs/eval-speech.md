# Measuring speech recognition and speaker separation

`Lorre eval-speech <manifest.json>` runs the same headless pipeline as `Lorre transcribe` over
recordings whose correct answer is known, and reports how many words it got wrong and how well it told
the speakers apart. Use it to decide whether a new speech or speaker model, or a setting, is better
than the current one: run both, compare the numbers on the same manifest.

```
Lorre eval-speech manifest.json [--limit N] [--json] [--no-diarization] [--quiet]
```

It writes nothing to the Lorre database or the export folder. Each item is processed in a temporary
folder that is removed afterwards. A missing audio file or reference file is reported for that item and
does not stop the run. Reference files and recordings can contain people's voices and words: keep them
outside the repository.

Lorre does not download anything. Fetching a dataset is a separate step that the owner decides on, after
checking the licence on the dataset's own page.

## Manifest

A JSON file next to the audio. Paths are relative to the manifest.

```json
{
  "name": "mini-set",
  "license": "as stated on the dataset page",
  "items": [
    {
      "id": "meeting-01",
      "audio": "audio/meeting-01.wav",
      "language": "nl",
      "referenceTextFile": "text/meeting-01.txt",
      "referenceRTTM": "rttm/meeting-01.rttm"
    },
    {
      "id": "short-clip",
      "audio": "audio/clip.wav",
      "language": "en",
      "referenceText": "the quick brown fox",
      "referenceTurns": [ { "speaker": "A", "startMs": 0, "endMs": 2400 } ]
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `id` | Name shown in the report. |
| `audio` | Audio or video file. |
| `microphoneAudio` | Optional second track. Accepted in the file, but the first version of the tool does not use it: only `audio` is run. |
| `language` | `nl`, `en`, ...; falls back to the language in the Lorre settings. Omit for automatic detection. |
| `referenceText` / `referenceTextFile` | The words that were said, inline or as a plain text file. Inline wins. Without it no WER is computed for the item. |
| `referenceTurns` / `referenceRTTM` | Who spoke when, as `{speaker, startMs, endMs}` turns, or an RTTM file (`SPEAKER <file> 1 <start s> <duration s> <NA> <NA> <name> <NA> <NA>`; other line types are ignored). Inline wins. Without it no speaker score is computed. |

## Reading the numbers

- **WER** (word error rate): (substitutions + deletions + insertions) / words in the reference. Lower is
  better. 0% is perfect; above 100% is possible with many insertions. The total pools all reference
  words, so a long recording weighs more than a short one. Text is lowercased and stripped of
  punctuation; apostrophes inside a word are dropped (`zo'n` becomes `zon`), hyphens separate words,
  and numbers are not converted (`2` and `twee` differ). Diacritics are kept. Reference transcripts
  that spell out numbers or leave out filler words ("uh") will score worse than the model deserves:
  compare models on the same reference, not references against each other.
- **Speakers found/expected**: distinct speakers in the output against the reference. More found than
  expected means one person was split over several labels.
- **Speaker accuracy**: of the reference speech where exactly one person talks, the share that lands on
  the right person. Output speakers are matched to reference speakers one-to-one, largest overlap first,
  so swapped labels cost nothing. The total is weighted by that scored time. It is not the diarization
  error rate (DER): stretches where the reference has overlap are skipped, and speech the system
  invents where the reference has none is not penalised. Treat it as "does the right person get the
  words", not as a published DER figure.
- **RTF** (real-time factor): processing time / audio duration. 0.1 means ten times faster than real
  time. It depends on the machine and on models already being warm; the first item of a run includes
  model loading.
- `--json` adds the identifiers of the speech engine and the speaker engine, so two runs can be told
  apart. The pipeline uses the Lorre settings for the speaker engine and an automatic speaker count, and
  `--no-diarization` measures the text alone.

## First measurements (14 November 2026)

Run on an M1 with 16 GB, with the pipeline as shipped (Parakeet TDT v3 for text, offline VBx for
speakers, automatic speaker count). The licences were read on the dataset pages on Hugging Face on the
day of the run; both state CC BY 4.0. The data is kept outside the repository.

| Set | What | Result |
|---|---|---|
| FLEURS Dutch, dev split (`google/fleurs`, `nl_nl`): 171 read sentences, 27 minutes, raw transcripts as reference | Text | WER 11.1% over 3,733 words; processing 45 s (RTF 0.03) |
| VoxConverse, first 10 clips of `dev-00000-of-00005.parquet` (`diarizers-community/voxconverse`): English broadcast clips, 42 minutes | Speakers | Speaker accuracy 72% over all clips; 87–96% on the four clips with two speakers; 50–61% on the clips with 4 and 17 speakers, where 2 and 3 were found; processing 101 s (RTF 0.04) |

Reading: these are the numbers to beat when a newer speech or speaker model is tried, on exactly these
files. They are not Lorre's real use. FLEURS is read speech, and part of the 11% is spelling of numbers
and names rather than misheard words; VoxConverse is English television with many speakers. Two-person
conversations, Lorre's main case, come out far better than crowded panels. No newer model has been
measured yet: the pipeline has one speech model wired in, and comparing another needs an adapter for it
first.

## Public datasets

Everything below is from memory and **not verified**. The licence of each dataset, and of each
individual recording in it, must be checked on the dataset's own page before use, certainly before
anything is copied, shared or used commercially. Where I am unsure, the table says so.

| Dataset | Contains | Licence as I know it | Confidence | Maps to the manifest |
|---|---|---|---|---|
| AMI Meeting Corpus | About 100 hours of English meetings, mostly four people, close-talk headset and far-field microphone recordings, with word-level transcripts and speaker segments. | Creative Commons Attribution 4.0 (CC BY 4.0), I believe. | Fairly confident, check. | Per-meeting transcript plus speaker segments, distributed in an XML annotation format and as RTTM in the common diarization setups: the RTTM goes in `referenceRTTM`; the words must first be exported to one plain text file per meeting (`referenceTextFile`) with the speakers' words in time order. Headset mixes or single far-field channels are the usual `audio`. |
| VoxConverse | Roughly 50 hours of multi-speaker "in the wild" video, mostly English news and debate, made for diarization only. | CC BY 4.0 according to the Hugging Face dataset card (checked 14 Nov 2026); the audio comes from YouTube videos. | Checked on the card. | RTTM per recording goes in `referenceRTTM`. No reference text, so only speaker numbers. The audio has to be obtained separately. |
| NOTSOFAR-1 | Microsoft's meeting dataset: real meetings recorded with several devices, with transcripts and speaker labels, from a 2024 challenge. English only. | I believe a Microsoft licence that allows research use, possibly CC BY; I do not remember the exact terms. | Not sure. | Transcripts are word-level with speaker and time. Convert to one text file and either RTTM or `referenceTurns`. The format is more elaborate than AMI; I am not sure of the file layout. |
| Common Voice (Dutch) | Short single-speaker read sentences from volunteers with their text. | CC0 (public domain dedication), I believe. | Fairly confident, check. | One short clip per item with `referenceText`. Good for WER on Dutch, useless for speakers (one speaker, no turns). Read speech is easier than conversation, so WER looks better than it will on real calls. |
| FLEURS (Dutch) | Read sentences in many languages, from Google, with transcripts. | CC BY 4.0 according to the Hugging Face dataset card (checked 14 Nov 2026). | Checked on the card. | Same as Common Voice: short clips with `referenceText`, WER only. Transcripts come in a raw and a normalised form; use whichever matches how you read the numbers, and keep it constant. |
| CGN (Corpus Gesproken Nederlands) | The Spoken Dutch Corpus, about 900 hours of Dutch and Flemish speech in many settings including conversations, with orthographic transcripts and speaker information. | A licence through the Instituut voor de Nederlandse Taal (Dutch Language Institute), not free to download. I am fairly sure access is by request and a fee or agreement. | Confident that it is restricted, unsure of the terms. | The best match for Dutch conversation, if access is arranged. Transcripts are in a Praat-like and XML format with speaker tiers: convert to a text file and `referenceTurns`. I do not remember the exact layout. |
| IFADV | A small corpus of informal Dutch face-to-face dialogues (about 20 recordings of a few minutes each) with orthographic transcripts and speech segments, from the University of Amsterdam. | I do not remember the licence; possibly free for research with a citation request, but I am not sure. | Unsure. | Two speakers per dialogue, close to Lorre's use. Transcripts in a Praat TextGrid format as far as I remember: convert to a text file and `referenceTurns`. Check the format and licence before relying on this. |

Notes on choosing:

- For Dutch conversation with speakers, only CGN and IFADV in this list are on topic, and both need
  their access terms checked. The rest are English meetings (AMI, VoxConverse, NOTSOFAR-1) or Dutch
  read speech without speakers (Common Voice, FLEURS).
- A small set you record yourself, with your own consent from the people in it and a transcript you
  have corrected by hand, will say more about Lorre's real use than any of these. It needs no licence
  check; keep it outside the repository.
- Convert to `referenceTurns` or RTTM using one name per person. The names in the reference never need
  to match the names in the output.
