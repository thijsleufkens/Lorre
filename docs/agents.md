# Lorre for agents

Lorre turns a conversation into a **record**: the transcript plus the outcomes the reviewer approved
(decisions, actions, commitments, information). Agents and scripts read that record; they never read
the database. The product reasoning is in
[the product spec](superpowers/specs/2026-11-13-lorre-product-spec.md) (sections 4.1, 4.2, 5 and 7.4).

## What a record is

- A **draft** (`recordVersion` 0) has the transcript only. It is written when a conversation has been
  transcribed and not yet reviewed. It never has outcomes.
- An **approved** record (`recordVersion` 1, 2, ...) has the approved outcomes. Every re-approval after
  a change is the next version. Proposals nobody approved are never in a record.
- `recordId` is stable per conversation. `schemaVersion` is the version of the file format.

Fields: `conversation` (id, title, type, startedAt, durationSeconds, participants), `outcomes` (id, kind,
text, ownerId, due, edited, evidence with segment ids and start/end in milliseconds), `transcript`
(engine, segments with participantId, startMs, endMs, text), `approvedAt`.

## The files

Records are written to the export folder from Lorre's settings, one pair per conversation:

```
<date> <title>.json    for agents
<date> <title>.md      for people
```

A re-approved record replaces the earlier files (same name, or the new name when the title changed).
`Lorre records --json` gives the exact `path` of each JSON file.

## Command line

All commands accept `--root <path>` to use another data folder (for testing). The binary is
`/Applications/Lorre.app/Contents/MacOS/Lorre`.

| Command | What it does |
|---|---|
| `Lorre records [--new --consumer NAME] [--status draft\|approved] [--json]` | The latest version of every exported record, newest first. `--new` leaves out what this consumer already marked. |
| `Lorre record <id-prefix> [--markdown]` | Prints the record JSON, or the readable Markdown. |
| `Lorre mark-processed <id-prefix> --consumer NAME [--version N]` | Marks a version (default: latest) as processed by this consumer. |
| `Lorre mcp` | Runs the MCP server on stdin/stdout. |

A record that is approved again after a change is **new** again for a consumer that marked the earlier
version.

## MCP server

`Lorre mcp` speaks the Model Context Protocol over stdio: newline-delimited JSON-RPC 2.0, nothing but
protocol messages on stdout. Add it to an agent, for example in a Claude Code `.mcp.json`:

```json
{
  "mcpServers": {
    "lorre": {
      "command": "/Applications/Lorre.app/Contents/MacOS/Lorre",
      "args": ["mcp"]
    }
  }
}
```

Tools:

| Tool | Arguments | Result |
|---|---|---|
| `list_records` | `consumer?`, `onlyNew?`, `status?` (`draft` or `approved`) | JSON array of listings |
| `get_record` | `recordId` (full id or unambiguous prefix) | the record as JSON |
| `mark_processed` | `recordId`, `consumer`, `version?` | a confirmation line |
| `get_transcript` | `recordId` | plain text, `[mm:ss] Speaker: text` per line |

A failing tool returns `isError: true` with a message to act on (unknown or ambiguous id, a record
file that is gone, a blank consumer name).

## Worked example: pick up what is new

An agent that files action items, calling itself `todo-agent`:

1. `list_records` with `{ "consumer": "todo-agent", "onlyNew": true, "status": "approved" }` returns
   the approved records it has not handled, for example one with `recordId`
   `3F2A9C10-...`, `recordVersion` 1, title "Call met Anna".
2. `get_record` with `{ "recordId": "3F2A9C10" }` returns the record. The agent reads
   `outcomes` where `kind` is `myAction` and creates its tasks, using `evidence.startMs` to point
   back to the moment in the conversation.
3. `mark_processed` with `{ "recordId": "3F2A9C10", "consumer": "todo-agent" }` records that version 1
   is handled. The next `list_records` with `onlyNew` no longer returns it, until the conversation is
   changed and approved again (version 2).

The same from a shell:

```bash
Lorre records --new --consumer todo-agent --status approved
Lorre record 3F2A9C10 --markdown
Lorre mark-processed 3F2A9C10 --consumer todo-agent
```
