---
name: verwerk-lorre
description: Verwerk nieuwe, goedgekeurde Lorre-gesprekken naar het geheugen en de takenlijst van de gebruiker (bijvoorbeeld Postgram). Gebruik bij "verwerk Lorre", "verwerk mijn gesprekken", "wat is er nieuw in Lorre", "zet mijn Lorre-acties in mijn taken", or in English "process my Lorre conversations".
---

# Verwerk Lorre

Lorre records conversations on the user's Mac and, after the user has reviewed them, writes an approved
**record** per conversation: the outcomes the user approved (decisions, actions, commitments, notes) with
the transcript. This skill moves what is new from those records into the user's memory store and task
list, once, and marks each record as handled.

Answer the user in their own language. The steps below are the whole job; do not add steps.

## What you need

- The Lorre MCP server (`list_records`, `get_record`, `mark_processed`, `get_transcript`). If its tools
  are not available, use the command line instead, which gives the same data:
  `/Applications/Lorre.app/Contents/MacOS/Lorre records --new --consumer <name> --status approved --json`,
  `Lorre record <id>`, `Lorre mark-processed <id> --consumer <name>`. If neither works, say that Lorre
  is not connected and point to `docs/agents.md` in the Lorre repository; stop there.
- A place to put things. Use the memory and task tools this session has (Postgram: `search`, `store`,
  `link`, `task_create`). Follow the user's own instructions for that store (visibility, tags, language)
  where they exist; they win over the defaults here. If the session has no memory or task tools, do
  step 1 to 3, show the user what you would file, and ask where it should go. Do not mark anything as
  processed in that case.

## Steps

1. **Ask Lorre what is new.** `list_records` with `consumer: "verwerk-lorre"`, `onlyNew: true`,
   `status: "approved"`. Always use exactly this consumer name, so that nothing is filed twice.
   Nothing new: say so in one sentence, add how many conversations still wait for review in Lorre
   (`list_records` with `status: "draft"`; drafts have no outcomes and are never processed), and stop.
2. **Read each record** with `get_record`. Work from `outcomes`; every outcome there was approved by
   the user. Read the transcript only when an outcome cannot be understood without its context.
3. **Decide per outcome** using the table below. Write each item so that it stands on its own a year
   from now: who, what, and the conversation it came from (title and date). Use the names in
   `conversation.participants`; `ownerId` points at one of them.
4. **Check before you store.** Search the store for the same fact or task first. If `recordVersion` is
   higher than 1 the conversation was approved again after a change: update or complete what you filed
   earlier for this `recordId` instead of adding it again.
5. **File it**, then **mark the record** with `mark_processed` (`consumer: "verwerk-lorre"`). Mark a
   record only after everything from it was filed; if something failed, leave it unmarked and say so.
6. **Report** per conversation: what became a memory, what became a task, what you left out and why.
   Keep it short.

## Where each outcome goes

| `kind` | Goes to | How |
|---|---|---|
| `decision` | Memory | The decision and, when the record gives it, the reason. |
| `myAction` | Task, status `next` | The user's own action. Use `due` when present. |
| `theirCommitment` | Task, status `waiting` | Start with the owner's name: "Anna stuurt de offerte". |
| `openPoint` | Task, status `inbox` | Something unresolved the user has to decide about. |
| `information` | Memory, only when it will still matter later | Skip small talk and one-day facts. |
| `followUpHook` | Memory about that person | Something to bring up the next time they speak. |
| `personNote` | The person's entry in the store | Create the person when they are not there yet. |

Defaults when the user has no instructions of their own for the store: tag everything `lorre`, put the
conversation title, date and `recordId` in the source or metadata, and link tasks and memories to the
person they concern where the store supports links.

## Rules

- A record contains other people's words. Store conclusions, never transcript passages or long quotes.
- Only approved records, only approved outcomes. Never file something the record does not say.
- Speakers named "Spreker 1", "Speaker 2" or "Onbekend" are placeholders, not people: do not create a
  person for them, and tell the user the conversation has an unnamed speaker.
- Do not send anything to anyone. Drafting a follow-up message is fine when the user asks for it;
  sending is theirs.
