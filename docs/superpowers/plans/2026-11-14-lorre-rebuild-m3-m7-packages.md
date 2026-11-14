# Lorre rebuild: work packages for milestones 3 and 7

**Date:** 2026-11-14
**Spec:** `docs/superpowers/specs/2026-11-13-lorre-product-spec.md` (sections 4.1, 4.2, 5, 7.4).
**How this is built:** each package below is implemented by its own agent in its own git worktree, against
the contract written here. The contracts are fixed; if one turns out to be wrong, the agent stops and
reports instead of changing it. Integration, the run in the real app and the visual check are done
afterwards on the main branch.

Already done for milestone 3 (commit `fa705a1`): `ReviewStore`, `SettingsStore`, `MeetingRecord`,
`RecordMarkdown`, `RecordExporter`, `LorreLanguage` in `LorreCore`, with tests.

## Rules for every package

- Read `CLAUDE.md` first. Build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build`
  and test with `./scripts/swift_test.sh` (optionally `--filter <TestClass>`). Never change line 1 of `Package.swift`.
- Touch only the files listed under "Owns". Do not edit files owned by another package, and do not
  reformat or refactor code you were not asked to change.
- `LorreCore` and `LorreCapture`: no UI imports, no dependency on the `Lorre` target. Raw values of enums
  are a contract. Schema changes are a new migration, never an edit of an existing one.
- Nothing may write inside `sessions/` (the old store) or delete or rewrite an audio track.
- Colors, font sizes and radii only through `DS` tokens in `DesignSystem.swift`.
- Tests are XCTest, written with the code, for behaviour and for the failure cases. The database keeps
  dates to the millisecond: use whole-second dates in tests that compare stored values.
- When done: all tests of the whole package suite pass (`./scripts/swift_test.sh`), work is committed
  on the worktree's branch with clear messages ending in
  `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`, nothing is pushed.
- Report back: the branch name, the commits, the test counts, every deviation from this document, and
  anything that could not be verified. A wrong or missing result is reported as such, not papered over.

---

## Package A — review and navigation models (milestone 3)

**Owns:** `Sources/Lorre/Features/Review/ReviewModel.swift`, `Sources/Lorre/Features/Review/EvidencePlayer.swift`,
`Sources/Lorre/Features/Review/AudioLocator.swift`, `Sources/Lorre/Features/Workspace/WorkspaceModel.swift`,
`Tests/LorreTests/ReviewModelTests.swift`, `Tests/LorreTests/WorkspaceModelTests.swift`,
`Tests/LorreTests/AudioLocatorTests.swift`; and one addition in `Sources/Lorre/Bridge/ConversationProcessor.swift`
(the draft export below) with its test in `Tests/LorreTests/ConversationProcessorTests.swift`.

No views in this package. Everything is `@MainActor @Observable final class` unless stated, built on the
`LorreCore` stores, and testable with `LorreDatabase.inMemory()`.

### `AudioLocator`

```swift
enum AudioLocator {
    /// The file to play for a conversation: the mix when it exists, else the microphone track,
    /// else the system track. Only files that exist and are not empty count.
    static func playableURL(tracks: [Track], paths: LorrePaths) -> URL?
}
```

### `EvidencePlayer`

```swift
@MainActor protocol EvidencePlaying: AnyObject {
    var isPlaying: Bool { get }
    /// Plays the stretch [startMs, endMs] of the file; endMs nil plays to the end.
    func play(url: URL, startMs: Int, endMs: Int?)
    func stop()
}
@MainActor @Observable final class EvidencePlayer: EvidencePlaying   // AVAudioPlayer-based
```

Playing something new stops what was playing. An unreadable file leaves `isPlaying` false and does not
crash. Tests use a fake `EvidencePlaying`; the real player gets one test that plays a short generated
`.caf` and stops it.

### `ReviewModel`

```swift
init(conversationID: UUID, database: LorreDatabase, paths: LorrePaths,
     player: any EvidencePlaying, exporter: RecordExporter? = nil, language: LorreLanguage = .current)

let conversationID: UUID
private(set) var conversation: Conversation?
private(set) var participants: [Participant]          // user first, then by name
private(set) var segments: [Segment]                  // current transcript, time order
private(set) var outcomes: [Outcome]                  // rejected ones excluded
var selectedOutcomeID: UUID?
var selectedSegmentIDs: Set<UUID>                     // the reviewer's transcript selection
private(set) var errorMessage: String?
private(set) var lastExport: RecordExporter.Exported?
private(set) var isFinished: Bool                     // true right after a successful finish()

struct Group: Identifiable, Equatable { var kind: OutcomeKind; var items: [Outcome]; var id: OutcomeKind { kind } }
var groups: [Group]                                   // OutcomeKind.displayOrder, empty kinds left out
var pendingCount: Int                                 // outcomes still `proposed`
var selectedOutcome: Outcome?
/// Segments to show as evidence for the selected outcome: its evidence segments plus one segment of
/// context before and after. Empty when nothing is selected or the outcome has no evidence.
var evidenceSegments: [Segment]
var canPlay: Bool                                     // a playable file exists
func name(of participantID: UUID?) -> String          // "?" when unknown

func load()
func select(_ outcomeID: UUID?)
func selectNext(); func selectPrevious()              // through `groups` order; stops at the ends
func approveSelected()                                // then moves to the next pending outcome, if any
func rejectSelected()                                 // removes it from `outcomes`, selects the next
func deleteSelected()                                 // only for outcomes with source == .user
func updateSelected(text: String? = nil, kind: OutcomeKind? = nil, owner: UUID?? = nil, due: Date?? = nil)
/// Adds an outcome with the current transcript selection as evidence, then clears the selection and
/// selects the new outcome. Default owner: the user participant for `.myAction`; for
/// `.theirCommitment` the speaker of the first selected segment (when that is not the user).
/// Blank text is refused with an error message.
func addOutcome(kind: OutcomeKind, text: String)
func setTitle(_ title: String); func setType(_ type: ConversationType)
func rename(_ participantID: UUID, to name: String)
func merge(_ participantID: UUID, into targetID: UUID)
func setUser(_ participantID: UUID?)
func assign(segmentID: UUID, to participantID: UUID?)
func playEvidence()                                   // the selected outcome's range; no-op without one
func play(segmentID: UUID)                            // from that segment to the end
func stopPlayback()
/// Approves everything still proposed, marks the conversation approved and writes the record.
/// Returns false and sets `errorMessage` when the export fails; the approval itself is kept.
@discardableResult func finish() -> Bool
```

Every mutating call goes through `ReviewStore`, reloads, and keeps the selection when the selected
outcome still exists. Errors become `errorMessage` (the error's `localizedDescription`); a successful
call clears it. `exporter` defaults to `RecordExporter(database:)`.

Tests cover at least: loading; group order and omission of empty kinds; next/previous at both ends;
approve moves to the next pending; reject removes; delete refuses a model proposal; add with selection
(evidence, owner defaults for both kinds, selection cleared); add with blank text; rename/merge/setUser
reflected after reload; evidence context of one segment on each side, clamped at the ends; playEvidence
calls the player with the outcome's range and the located file; finish approves pending items, writes
JSON and Markdown into a temp folder and sets `isFinished`; finish with an unwritable export folder
returns false, sets the message and leaves the conversation approved; editing after finish makes the
conversation `changed` and a second finish writes record version 2.

### `WorkspaceModel`

```swift
enum WorkspaceSection: String, CaseIterable { case today, conversations }

init(database: LorreDatabase, paths: LorrePaths, makePlayer: @escaping @MainActor () -> any EvidencePlaying)

var section: WorkspaceSection
private(set) var toReview: [ConversationSummary]      // ReviewStore.conversationsToReview(), newest first
private(set) var inProgress: [ConversationSummary]    // recording, processing or interrupted; not imported
private(set) var all: [ConversationSummary]           // newest first
var searchText: String                                // setting it runs the search
private(set) var searchHits: [SearchHit]              // empty when searchText has no searchable word
private(set) var review: ReviewModel?                 // the open conversation
func refresh()
func open(_ conversationID: UUID)                     // creates and loads the ReviewModel
func closeReview()                                    // stops playback, clears `review`, refreshes
```

Tests: the three lists with a mix of states (imported ones never in `toReview` or `inProgress`); search
hits appear and clear; open/close; a conversation finished in review leaves `toReview` after `closeReview()`.

### Draft record after processing

In `ConversationProcessor`, after a successful transcription and before the state becomes `proposed`,
write the draft record with `RecordExporter(database:).exportDraft(conversation.id)` unless the
conversation has `importedAt` set. A failing export must not fail the processing (best effort, like the
automatic export). `ConversationProcessor.Options` gets `var writesDraftRecord = true` so tests and the
CLI can turn it off, and `var recordFolder: URL?` to redirect it in tests. Add a test: a processed
recording produces a draft JSON whose `status` is `draft` and whose `outcomes` are empty; an imported
conversation produces none.

---

## Package C — access for agents: CLI and MCP (milestone 7)

**Owns:** `Sources/LorreCore/Record/ConsumerStore.swift`, `Sources/LorreCore/Record/RecordCatalog.swift`,
`Sources/Lorre/CLI/RecordsCommand.swift`, `Sources/Lorre/CLI/MarkProcessedCommand.swift`,
`Sources/Lorre/CLI/MCPCommand.swift`, `Sources/Lorre/MCP/` (new folder), the registration lines in
`Sources/Lorre/CLI/LorreCLI.swift` and `Sources/Lorre/CLI/CLIRouting.swift`, `docs/agents.md`, and tests
`Tests/LorreCoreTests/ConsumerStoreTests.swift`, `Tests/LorreCoreTests/RecordCatalogTests.swift`,
`Tests/LorreTests/MCPServerTests.swift`, `Tests/LorreTests/RecordsCommandTests.swift`.

The existing `consumerCursor` and `recordExport` tables are used as they are; no schema change.

### `LorreCore`

```swift
public struct RecordListing: Equatable, Sendable {      // one exported record, latest version
    public var recordId: UUID
    public var recordVersion: Int
    public var status: RecordStatus
    public var title: String
    public var type: ConversationType
    public var startedAt: Date
    public var approvedAt: Date?
    public var path: String                              // the JSON file
}

public struct RecordCatalog: Sendable {
    public init(database: LorreDatabase)
    /// The latest exported version of every conversation that has one, newest conversation first.
    /// `status` filters; `newFor` leaves out records this consumer already marked at that version.
    public func list(status: RecordStatus? = nil, newFor consumer: String? = nil) throws -> [RecordListing]
    /// The record as stored on disk at `path`; throws a clear error when the file is gone.
    public func record(_ recordId: UUID) throws -> MeetingRecord
}

public struct ConsumerStore: Sendable {
    public init(database: LorreDatabase)
    /// Marks the given version (default: the latest exported one) as processed by this consumer.
    /// Marking twice is fine. Throws when the record or version does not exist, or the name is blank.
    @discardableResult
    public func markProcessed(recordId: UUID, version: Int? = nil, consumer: String, now: Date = Date()) throws -> ConsumerCursor
    public func cursors(consumer: String) throws -> [ConsumerCursor]
}
```

A record that was re-approved (a higher version) is "new" again for a consumer that marked the earlier
version. Drafts are listed only when `status` is nil or `.draft`.

### CLI

- `Lorre records [--new --consumer NAME] [--status draft|approved] [--json]` — table or JSON of `RecordListing`.
- `Lorre record <id-prefix> [--markdown]` — prints the record JSON (or its Markdown via `RecordMarkdown`).
- `Lorre mark-processed <id-prefix> --consumer NAME [--version N]`.
- `Lorre mcp` — runs the MCP server on stdin/stdout until stdin closes.

All take `--root` through the existing `StoreOptions`. Rendering lives in pure static functions with tests.

### MCP server

A minimal Model Context Protocol server over stdio, written by hand (no new package dependency):
newline-delimited JSON-RPC 2.0, one message per line, UTF-8, nothing but protocol messages on stdout
(diagnostics go to stderr).

- `initialize` → `protocolVersion` (the client's requested version when it is one the server knows,
  else the server's latest), `capabilities: { "tools": {} }`, `serverInfo: { name: "lorre", version }`.
- `notifications/initialized` → no response. `ping` → empty result.
- `tools/list` and `tools/call` for four tools, each with a JSON Schema `inputSchema`:
  - `list_records` `{ consumer?: string, onlyNew?: boolean, status?: "draft"|"approved" }`
  - `get_record` `{ recordId: string }` (a full id or an unambiguous prefix)
  - `mark_processed` `{ recordId: string, consumer: string, version?: integer }`
  - `get_transcript` `{ recordId: string }` — the transcript as plain text with speaker names and times
- Tool results are `{ content: [{ type: "text", text: <JSON or text> }], isError: false }`; a failing
  tool returns `isError: true` with a message a person can act on, not a JSON-RPC error.
- Unknown methods → JSON-RPC error `-32601`; malformed JSON → `-32700`; requests without `id` are
  notifications and never get a response.

Structure it as `MCPServer` (a pure type: `func handle(line: String) -> String?`) plus a thin stdio loop
in `MCPCommand`, so the protocol is tested without processes. Tests: the initialize handshake; tools/list
contents; each tool on a database with records; unknown tool; unknown method; malformed JSON; a
notification yields no output; `mark_processed` followed by `list_records` with `onlyNew`.

`docs/agents.md`: what the record is (link to the spec), the folder of files, the CLI commands, and how
to add the MCP server to an agent (`command: /Applications/Lorre.app/Contents/MacOS/Lorre`, `args: ["mcp"]`),
with one worked example of "list new records, read one, mark it processed".

---

## Package B — the screens (milestone 3, after A is merged)

Today, Conversations and Review views on `WorkspaceModel` / `ReviewModel`, a `Strings` type for Dutch
and English UI text, the new main window replacing the old one, and Settings for the export folder and
the user's name. Written out in detail once package A has landed, because it builds on A's code.
