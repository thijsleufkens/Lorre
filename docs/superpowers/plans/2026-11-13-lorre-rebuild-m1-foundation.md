# Lorre rebuild, milestone 1: Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lay the base of the rebuilt Lorre: a GUI-free `LorreCore` module with the new domain model and a SQLite store, a one-time import of the existing sessions, a `list` command that reads from the database, and a build that is signed with a stable identity so permissions survive rebuilds.

**Done when (from the spec):** existing conversations are listed from the database, and a rebuild keeps microphone and audio-capture permissions.

**Architecture:** A new SwiftPM library target `LorreCore` sits next to the existing executable target. It contains only new code: domain types, the GRDB-backed store, and a legacy importer that reads the old `session.json` / `transcript.json` files with its own minimal decoders. The existing target depends on `LorreCore` and gains two CLI subcommands. Nothing in the existing app's behaviour changes in this milestone; the old UI keeps running on the old file store until milestones 2–3 replace it.

**Tech Stack:** Swift 6 / SwiftPM, GRDB 7 (SQLite, FTS5), swift-argument-parser, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-13-lorre-product-spec.md` (sections 5, 6, 7, 9, 11).

---

## Decisions taken for this milestone

| Decision | Reason |
|---|---|
| `LorreCore` is new code only; capture and speech code stay in the existing target for now | Moving 17k lines across module boundaries is mechanical churn with no user value yet. `LorreCapture` is extracted in milestone 2 and `LorreSpeech` in milestone 4, when that code is being changed anyway. |
| The importer has its own decoders for the legacy JSON | `LorreCore` must not depend on the legacy target (the dependency points the other way). The importer only needs a handful of fields. |
| Legacy data is read in place and never modified | The old app keeps working during the rebuild, and the import can be re-run. Audio is referenced by path, not copied. |
| The database lives at `~/Library/Application Support/Lorre/lorre.sqlite` | Same root the app already owns. |
| Imported conversations get `importedAt` set and state `proposed` | They have a transcript and no outcomes. `importedAt` lets Today (milestone 3) leave them out of "to review" until the user opens one. |
| Segments belong to a `transcriptVersion` row | Provenance and re-processing are a spec principle (7.1); adding the table later would mean migrating every segment. |
| Platform minimum goes to macOS 26 now | Decided in the spec; doing it first surfaces deprecation fallout early. |
| Signing identity comes from `LORRE_SIGN_IDENTITY`, ad-hoc remains the default | Keeps CI and other machines working; Thijs sets it once. |

## Toolchain note

`Package.swift` declares tools-version 6.3. The machine now has Swift 6.4 (Command Line Tools) and 6.4.2 (Xcode), and `swift package dump-package` succeeds with both, so the "lower the tools-version to 6.2" workaround in `CLAUDE.md` should no longer be needed. Task 0 confirms this with a full build and updates `CLAUDE.md`. If it does not hold, keep using the documented workaround and never commit a tools-version change.

## File structure

- Modify `Package.swift` — GRDB dependency, `LorreCore` + `LorreCoreTests` targets, macOS 26.
- Create `Sources/LorreCore/Domain/Conversation.swift` — `Conversation`, `ConversationType`, `ConversationState`.
- Create `Sources/LorreCore/Domain/People.swift` — `Person`, `Participant`.
- Create `Sources/LorreCore/Domain/Transcript.swift` — `Track`, `TrackKind`, `TranscriptVersion`, `Segment`.
- Create `Sources/LorreCore/Domain/Outcome.swift` — `Outcome`, `OutcomeKind`, `OutcomeStatus`, `OutcomeSource`.
- Create `Sources/LorreCore/Domain/Record.swift` — `RecordExport`, `RecordStatus`, `ConsumerCursor`.
- Create `Sources/LorreCore/Store/LorreDatabase.swift` — opens the database, runs migrations.
- Create `Sources/LorreCore/Store/Schema.swift` — migration `v1`.
- Create `Sources/LorreCore/Store/ConversationStore.swift` — reads and writes.
- Create `Sources/LorreCore/Store/SearchStore.swift` — FTS5 search.
- Create `Sources/LorreCore/Import/LegacySessionImporter.swift` — legacy sessions → database.
- Create `Sources/LorreCore/Support/LorrePaths.swift` — application-support locations.
- Create `Sources/Lorre/CLI/ListCommand.swift`, `Sources/Lorre/CLI/ImportLegacyCommand.swift`.
- Modify `Sources/Lorre/CLI/LorreCLI.swift`, `Sources/Lorre/CLI/CLIRouting.swift`.
- Modify `scripts/package_macos_app.sh` — signing identity.
- Create `docs/signing.md` — how to create and use the self-signed identity.
- Create `Tests/LorreCoreTests/…` — one test file per store/importer file, plus `Fixtures/legacy/`.
- Modify `CLAUDE.md` — toolchain note, new module, new commands.

---

## Task 0: Baseline and toolchain

- [x] Run `swift build` and `./scripts/swift_test.sh` on the untouched branch. Record the test count and any failures in the PR description; later tasks must not reduce it.
- [x] If both succeed without lowering the tools-version: rewrite the "Toolchain quirk" section of `CLAUDE.md` to say that Swift 6.4+ builds the package directly, and keep one sentence on the old workaround for older toolchains.
- [x] If they fail on the tools-version: leave `CLAUDE.md` as is and use the workaround for every later step.
- [x] Commit: `docs: toolchain note after Swift 6.4`.

## Task 1: Package layout

- [x] In `Package.swift`: set `platforms: [.macOS(.v26)]`; add `.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")`; add

```swift
.target(
    name: "LorreCore",
    dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
),
.testTarget(
    name: "LorreCoreTests",
    dependencies: ["LorreCore"],
    resources: [.copy("Fixtures")]
),
```

  and add `"LorreCore"` to the dependencies of the `Lorre` target.
- [x] Create `Sources/LorreCore/Support/LorrePaths.swift`:

```swift
import Foundation

/// Locations Lorre owns on disk. Everything is under one root so tests can point it at a temp folder.
public struct LorrePaths: Sendable {
    public let root: URL

    public init(root: URL = LorrePaths.defaultRoot()) { self.root = root }

    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Lorre", isDirectory: true)
    }

    public var database: URL { root.appendingPathComponent("lorre.sqlite") }
    /// New conversations (from milestone 2 on) store their tracks here.
    public var conversations: URL { root.appendingPathComponent("conversations", isDirectory: true) }
    /// The pre-rebuild store. Read-only for the new code.
    public var legacySessions: URL { root.appendingPathComponent("sessions", isDirectory: true) }
}
```

- [x] Add a first test `Tests/LorreCoreTests/LorrePathsTests.swift` asserting the three derived paths for a given root. Create `Tests/LorreCoreTests/Fixtures/.gitkeep`.
- [x] `swift build` and `swift test --filter LorreCoreTests`. Fix macOS 26 deprecation errors in the legacy target only as far as needed to compile; list remaining warnings in the PR.
- [x] Commit: `build: add LorreCore module, GRDB, macOS 26 minimum`.

## Task 2: Domain types

All types are `public`, `Codable`, `Equatable`, `Sendable`, with a memberwise `public init`. Enums are `String`-backed; their raw values are stored in the database and exported in records, so they are part of the contract.

- [x] Write `Tests/LorreCoreTests/DomainRawValueTests.swift` first: one assertion per enum case pinning its raw value (for example `XCTAssertEqual(OutcomeKind.theirCommitment.rawValue, "theirCommitment")`). This is the guard against accidental renames.
- [x] Create the types:

```swift
// Conversation.swift
public enum ConversationType: String, Codable, CaseIterable, Sendable { case workMeeting, intake, network, other }
public enum ConversationState: String, Codable, CaseIterable, Sendable {
    case recording, interrupted, processing, proposed, approved, changed
}
public struct Conversation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var type: ConversationType
    public var state: ConversationState
    public var startedAt: Date
    public var durationSeconds: Double?
    public var calendarEventId: String?
    public var importedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
}

// People.swift
public struct Person: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var organisation: String?
    public var role: String?
    public var notes: String?
}
public struct Participant: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var conversationId: UUID
    public var personId: UUID?
    public var name: String
    public var isUser: Bool
    /// The speaker label the engine produced ("S1", "UNK"); kept so re-processing can re-map.
    public var sourceLabel: String?
}

// Transcript.swift
public enum TrackKind: String, Codable, CaseIterable, Sendable { case mix, microphone, system, device }
public struct Track: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var conversationId: UUID
    public var kind: TrackKind
    /// Path relative to `LorrePaths.root`.
    public var relativePath: String
}
public struct TranscriptVersion: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var conversationId: UUID
    public var engine: String
    public var modelVersion: String?
    public var settingsJSON: String?
    public var languageHint: String?
    public var isCurrent: Bool
    public var createdAt: Date
}
public struct Segment: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var transcriptVersionId: UUID
    public var participantId: UUID?
    public var startMs: Int
    public var endMs: Int
    public var text: String
    public var confidence: Double?
    public var isEdited: Bool
}

// Outcome.swift
public enum OutcomeKind: String, Codable, CaseIterable, Sendable {
    case decision, myAction, theirCommitment, openPoint, information, followUpHook, personNote
}
public enum OutcomeStatus: String, Codable, CaseIterable, Sendable { case proposed, approved, rejected }
public enum OutcomeSource: String, Codable, CaseIterable, Sendable { case model, user, agent }
public struct Outcome: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var conversationId: UUID
    public var kind: OutcomeKind
    public var text: String
    public var ownerParticipantId: UUID?
    public var due: Date?
    public var status: OutcomeStatus
    public var edited: Bool
    public var source: OutcomeSource
    public var evidenceSegmentIds: [UUID]
    public var evidenceStartMs: Int?
    public var evidenceEndMs: Int?
    public var createdAt: Date
}

// Record.swift
public enum RecordStatus: String, Codable, CaseIterable, Sendable { case draft, approved }
public struct RecordExport: Codable, Equatable, Sendable {
    public var conversationId: UUID
    public var version: Int
    public var status: RecordStatus
    public var approvedAt: Date?
    public var path: String
}
public struct ConsumerCursor: Codable, Equatable, Sendable {
    public var consumerName: String
    public var conversationId: UUID
    public var recordVersion: Int
    public var processedAt: Date
}
```

- [x] Run the tests; commit: `feat(core): domain model for conversations, people, outcomes, records`.

## Task 3: Database and schema

- [x] Test first, `Tests/LorreCoreTests/LorreDatabaseTests.swift`:
  - an in-memory database opens and migration `v1` creates every table below;
  - opening the same file twice does not re-run the migration;
  - deleting a conversation removes its participants, tracks, transcript versions, segments and outcomes (foreign keys cascade);
  - inserting a segment with an unknown `transcriptVersionId` fails.
- [x] Create `Sources/LorreCore/Store/LorreDatabase.swift`: a `public final class LorreDatabase: Sendable` wrapping a GRDB `DatabaseQueue`, with `public init(url: URL) throws` (creates the parent folder, enables foreign keys) and `public static func inMemory() throws -> LorreDatabase`. Both run `Schema.migrator.migrate(_:)`.
- [x] Create `Sources/LorreCore/Store/Schema.swift` with one registered migration, `v1`:

```sql
CREATE TABLE conversation (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  type TEXT NOT NULL,
  state TEXT NOT NULL,
  startedAt DATETIME NOT NULL,
  durationSeconds DOUBLE,
  calendarEventId TEXT,
  importedAt DATETIME,
  createdAt DATETIME NOT NULL,
  updatedAt DATETIME NOT NULL
);
CREATE INDEX conversation_startedAt ON conversation(startedAt);

CREATE TABLE person (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  organisation TEXT,
  role TEXT,
  notes TEXT
);

CREATE TABLE participant (
  id TEXT PRIMARY KEY NOT NULL,
  conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
  personId TEXT REFERENCES person(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  isUser BOOLEAN NOT NULL DEFAULT 0,
  sourceLabel TEXT
);
CREATE INDEX participant_conversation ON participant(conversationId);
CREATE INDEX participant_person ON participant(personId);

CREATE TABLE track (
  id TEXT PRIMARY KEY NOT NULL,
  conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  relativePath TEXT NOT NULL
);

CREATE TABLE transcriptVersion (
  id TEXT PRIMARY KEY NOT NULL,
  conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
  engine TEXT NOT NULL,
  modelVersion TEXT,
  settingsJSON TEXT,
  languageHint TEXT,
  isCurrent BOOLEAN NOT NULL,
  createdAt DATETIME NOT NULL
);
CREATE UNIQUE INDEX transcriptVersion_current
  ON transcriptVersion(conversationId) WHERE isCurrent = 1;

CREATE TABLE segment (
  id TEXT PRIMARY KEY NOT NULL,
  transcriptVersionId TEXT NOT NULL REFERENCES transcriptVersion(id) ON DELETE CASCADE,
  participantId TEXT REFERENCES participant(id) ON DELETE SET NULL,
  startMs INTEGER NOT NULL,
  endMs INTEGER NOT NULL,
  text TEXT NOT NULL,
  confidence DOUBLE,
  isEdited BOOLEAN NOT NULL DEFAULT 0
);
CREATE INDEX segment_version_start ON segment(transcriptVersionId, startMs);

CREATE TABLE outcome (
  id TEXT PRIMARY KEY NOT NULL,
  conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  text TEXT NOT NULL,
  ownerParticipantId TEXT REFERENCES participant(id) ON DELETE SET NULL,
  due DATETIME,
  status TEXT NOT NULL,
  edited BOOLEAN NOT NULL DEFAULT 0,
  source TEXT NOT NULL,
  evidenceSegmentIds TEXT NOT NULL DEFAULT '[]',
  evidenceStartMs INTEGER,
  evidenceEndMs INTEGER,
  createdAt DATETIME NOT NULL
);
CREATE INDEX outcome_conversation ON outcome(conversationId);

CREATE TABLE recordExport (
  conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  status TEXT NOT NULL,
  approvedAt DATETIME,
  path TEXT NOT NULL,
  PRIMARY KEY (conversationId, version)
);

CREATE TABLE consumerCursor (
  consumerName TEXT NOT NULL,
  conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
  recordVersion INTEGER NOT NULL,
  processedAt DATETIME NOT NULL,
  PRIMARY KEY (consumerName, conversationId, recordVersion)
);

CREATE VIRTUAL TABLE segmentSearch USING fts5(
  text, content='segment', content_rowid='rowid', tokenize='unicode61 remove_diacritics 2'
);
```

  Use GRDB's `synchronize(withTable:)` for `segmentSearch` (it creates the triggers) rather than hand-written triggers. UUIDs are stored as uppercase strings; make that explicit in the record conformances so ids match the legacy folder names.
- [x] Make the domain types conform to GRDB's `FetchableRecord` and `PersistableRecord` in `LorreCore/Store/Records.swift`, with `databaseTableName` matching the table names above. `evidenceSegmentIds` is stored as a JSON string. Check the exact GRDB 7 API against the resolved package rather than from memory.
- [x] Run the tests; commit: `feat(core): SQLite store with schema v1`.

## Task 4: ConversationStore

- [x] Test first, `Tests/LorreCoreTests/ConversationStoreTests.swift`, against an in-memory database:
  - `save(_:)` then `conversation(id:)` round-trips every field;
  - `listConversations()` returns newest `startedAt` first, each with its participant names, segment count of the current transcript version, and outcome counts per status;
  - `saveTranscript(...)` inserts a version with its segments in one transaction and clears `isCurrent` on the previous version;
  - `currentSegments(conversationId:)` returns only the current version, ordered by `startMs`;
  - saving a conversation that already exists updates it without touching its children.
- [x] Implement `Sources/LorreCore/Store/ConversationStore.swift`:

```swift
public struct ConversationSummary: Equatable, Sendable {
    public var conversation: Conversation
    public var participantNames: [String]
    public var segmentCount: Int
    public var proposedOutcomes: Int
    public var approvedOutcomes: Int
}

public struct ConversationStore: Sendable {
    public init(database: LorreDatabase)
    public func save(_ conversation: Conversation) throws
    public func conversation(id: UUID) throws -> Conversation?
    public func listConversations() throws -> [ConversationSummary]
    public func saveParticipants(_ participants: [Participant]) throws
    public func participants(conversationId: UUID) throws -> [Participant]
    public func saveTracks(_ tracks: [Track]) throws
    public func saveTranscript(version: TranscriptVersion, segments: [Segment]) throws
    public func currentSegments(conversationId: UUID) throws -> [Segment]
    public func delete(conversationId: UUID) throws
}
```

  `listConversations()` is one query with sub-selects, not a query per conversation.
- [x] Run the tests; commit: `feat(core): conversation store`.

## Task 5: Search

- [x] Test first, `Tests/LorreCoreTests/SearchStoreTests.swift`: two conversations with different text; a query for a word returns only the matching conversation with the segment id, its start time and a snippet; a prefix query (`maak*`) matches `maakindustrie`; segments of a non-current transcript version are not returned; an empty or punctuation-only query returns no results and does not throw.
- [x] Implement `Sources/LorreCore/Store/SearchStore.swift` with `public func search(_ query: String, limit: Int = 50) throws -> [SearchHit]`. Build the FTS pattern with GRDB's `FTS5Pattern(matchingAllPrefixesIn:)` so user input cannot produce a syntax error.
- [x] Run the tests; commit: `feat(core): full-text search over transcripts`.

## Task 6: Legacy importer

Mapping:

| Legacy | New |
|---|---|
| `session.json` `id` (or folder name when they differ) | `Conversation.id` |
| `title` | `title` |
| `recordedAt ?? createdAt` | `startedAt` |
| `durationSeconds` | `durationSeconds` |
| `status` `ready` with a transcript | state `proposed` |
| `status` `processing`, `recording`, `error`, `idle`, or `ready` without a transcript | state `interrupted` |
| — | `type` `.other`, `importedAt` = now |
| `audioFileName`, `microphoneStemFileName`, `systemAudioStemFileName`, when the file exists | `Track` rows (`mix`, `microphone`, `system`) with `relativePath` `sessions/<id>/<file>` |
| `transcript.json` `speakers[]` | one `Participant` each: `name` = `displayName`, `sourceLabel` = `id`, `isUser` false |
| `transcript.json` `sourceEngine`, `languageHint`, `createdAt` | one `TranscriptVersion`, `isCurrent` true |
| `transcript.json` `segments[]` | `Segment` rows; `speakerId` mapped to the participant with that `sourceLabel` |

- [x] Create fixtures under `Tests/LorreCoreTests/Fixtures/legacy/`: copy `session-manifest-v1-with-version.json`, `session-manifest-v1-pre-version.json` and `transcript-document-v1.json` from `Tests/LorreTests/Fixtures/`. The tests assemble them into temporary `sessions/<uuid>/` folders.
- [x] Test first, `Tests/LorreCoreTests/LegacySessionImporterTests.swift`:
  - a session with a transcript imports as one conversation with two participants, one current transcript version and the right number of segments, each segment linked to the right participant;
  - a pre-version manifest (no `schemaVersion`) imports;
  - a session without `transcript.json` imports as `interrupted` with no transcript version;
  - only track files that exist on disk become `Track` rows;
  - running the import twice leaves exactly one conversation and does not duplicate participants or segments;
  - a conversation whose `importedAt` is set but that has since been changed in the database (for example its title) is not overwritten by a second import;
  - a folder with a corrupt `session.json` is skipped and reported, and the other sessions still import;
  - a folder whose name differs from the `id` inside the JSON uses the folder name;
  - the importer never writes inside the legacy folder (compare a recursive listing with modification dates before and after).
- [x] Implement `Sources/LorreCore/Import/LegacySessionImporter.swift`:

```swift
public struct LegacyImportReport: Equatable, Sendable {
    public var imported: [UUID] = []
    public var alreadyPresent: [UUID] = []
    public var skipped: [Skipped] = []
    public struct Skipped: Equatable, Sendable { public var folder: String; public var reason: String }
}

public struct LegacySessionImporter: Sendable {
    public init(paths: LorrePaths, store: ConversationStore, now: @escaping @Sendable () -> Date = Date.init)
    public func run() throws -> LegacyImportReport
}
```

  Private `Decodable` structs hold only the fields in the mapping table, every one optional except `title`, decoded with `.iso8601` dates. Each session is imported in a single transaction. "Already present" is decided by `store.conversation(id:) != nil`; such sessions are left untouched.
- [x] Run the tests; commit: `feat(core): import legacy sessions into the database`.

## Task 7: CLI commands

- [x] Extend `Tests/LorreTests/CLIRoutingTests.swift` first: `list` and `import-legacy` route to the CLI.
- [x] Add both names to `CLIRouting.subcommands` and both commands to `LorreCLI.configuration.subcommands`.
- [x] Create `Sources/Lorre/CLI/ImportLegacyCommand.swift`: opens `LorreDatabase(url: LorrePaths().database)`, runs the importer, prints `Imported N, already present M, skipped K` and one line per skipped folder with its reason. Exit code 0 unless the database cannot be opened.
- [x] Create `Sources/Lorre/CLI/ListCommand.swift`: prints one line per conversation, newest first — date, duration in minutes, state, segment count, title — and supports `--json` (an array with `id`, `title`, `type`, `state`, `startedAt`, `durationSeconds`, `participants`, `segmentCount`, `proposedOutcomes`, `approvedOutcomes`). An optional `--root <path>` overrides the application-support root for both commands, so they can be tested against a temp folder.
- [x] Put the formatting in a pure function `ListCommand.render(_ summaries: [ConversationSummary], json: Bool) -> String` and test it in `Tests/LorreTests/ListCommandTests.swift` (plain and JSON output, empty list).
- [x] Build, then run against a temp root seeded with the fixtures: `swift run Lorre import-legacy --root <tmp>` followed by `swift run Lorre list --root <tmp>`.
- [x] Commit: `feat(cli): import-legacy and list commands on the new store`.

## Task 8: Stable signing identity

- [x] In `scripts/package_macos_app.sh`, replace the hard-coded `--sign -` with an identity taken from `LORRE_SIGN_IDENTITY` (default `-`), echo which identity is used, and after signing print the designated requirement (`codesign -d -r- "$APP_BUNDLE"`).
- [x] Write `docs/signing.md`:
  - why: with ad-hoc signing the designated requirement is the binary hash, so every build resets permissions; with a fixed certificate it is the certificate, so they persist;
  - how Thijs creates the certificate himself in Keychain Access (Certificate Assistant → Create a Certificate → name `Lorre Local Signing`, identity type Self-Signed Root, certificate type Code Signing), and that the first `codesign` asks once for keychain access;
  - usage: `LORRE_SIGN_IDENTITY="Lorre Local Signing" ./scripts/package_macos_app.sh release`;
  - note that the keychain already contains an "Apple Development" identity, which also gives a stable requirement on this Mac but expires and is tied to one Apple ID, so the self-signed certificate is the one to standardise on;
  - what other users see (one-time "Open Anyway"), and that Sparkle update signing is separate and comes in milestone 8.
- [ ] **Manual verification by Thijs** (cannot be automated; record the outcome in the PR):
  1. create the certificate; package and install with `LORRE_SIGN_IDENTITY` set; grant microphone and system-audio permission; make a 10-second mic+system recording and confirm both tracks contain audio;
  2. change one line of code, package and install again with the same identity;
  3. record again without being asked for permission, and confirm both tracks contain audio (silent system audio means the grant did not carry over, even without a prompt).
- [ ] If step 3 fails, do not work around it: note the result in `docs/signing.md` and in the spec's open questions, since it affects distribution.
- [x] Commit: `build: sign with a configurable identity so permissions survive rebuilds`.

## Task 9: End-to-end check and documentation

- [x] Back up first: copy `~/Library/Application Support/Lorre/sessions` to a dated folder under `~/Documents`. The importer does not write there, but this is the user's only copy.
- [x] Run `Lorre import-legacy` against the real root and then `Lorre list`. Expected: all 12 existing sessions are listed (or each missing one is explained by a "skipped" line), and the 8 Oct 2026 conversation shows 382 segments.
- [x] Run it a second time: `Imported 0, already present 12`.
- [x] Open the existing app and confirm it still lists and plays its sessions (the old store is untouched).
- [x] `./scripts/ci_check.sh` passes; the legacy test count is not lower than in Task 0.
- [x] Update `CLAUDE.md`: the `LorreCore` module and its rule (no UI imports, no dependency on the legacy target), the database location, the two commands, the signing variable, and that the old file store is legacy and read-only for new code.
- [x] Commit: `docs: describe LorreCore, the database and the new commands`.

---

## Execution notes (2026-11-13)

- Tasks 0–7 and 9 are done; Task 8 is implemented but its manual permission check is still open.
- Toolchain: the tools-version workaround is no longer needed, but Xcode's toolchain is. The Command
  Line Tools open the package and then fail on the SwiftUI macros.
- `LegacySessionImporter` takes the `LorreDatabase` rather than a `ConversationStore`, because each
  session is written in a single transaction.
- A session whose transcript file is unreadable is skipped and reported instead of being imported empty.
  A session that never reached `ready` keeps its partial transcript and is imported as `interrupted`.
- Task 9 backed up the session metadata (the JSON files, 572 KB) rather than all 4.9 GB: the importer
  never opens audio for writing, and a before/after listing of the legacy folder was identical.
- Result on the real data: 12 imported, 0 skipped; second run 0 imported, 12 already present; the
  8 Oct 2026 conversation has 382 segments.
- Tests: 111 before; 118 in `LorreTests` plus 41 in `LorreCoreTests` after.
- Not checked: opening the old app's window after the import (its files are byte-for-byte unchanged).

## Out of scope for this milestone

- Any change to recording, processing or the existing UI (milestones 2–4).
- Writing records or outcomes; the tables exist, nothing fills them yet (milestone 3).
- People: the `person` table stays empty; participants are linked to people at approval (milestone 6).
- Extracting `LorreCapture` and `LorreSpeech` into their own targets (milestones 2 and 4).
- Sparkle, onboarding, download page (milestone 8).

## Risks

| Risk | Handling |
|---|---|
| macOS 26 minimum breaks the legacy target's build | Task 1 fixes compile errors only; warnings are listed, not chased. |
| GRDB 7 API differs from what this plan assumes | The plan fixes the schema and the public store API, not GRDB call sites; verify against the resolved package. |
| Self-signed identity does not preserve TCC grants | Task 8 measures it before anything depends on it. |
| Import meets an unexpected legacy file shape in real data | Every field optional except the title; corrupt sessions are skipped and reported; Task 9 runs on the real data. |
