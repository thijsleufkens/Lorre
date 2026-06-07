# Lorre → Strongbad Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On every finished session, Lorre writes both a Markdown file and a JSON envelope to the configured cloud-synced folder, with the transcript's `languageHint` reflecting the chosen batch language, so the Strongbad VPS can ingest meetings.

**Architecture:** Extend the existing automatic-export path (`AppViewModel.performAutomaticMarkdownExportIfNeeded`) to also write a `.json` sidecar reusing `MarkdownExportService`'s JSON payload (`{session, transcript, exportedAt}`). Thread the chosen language code from `AppViewModel.launchProcessing` → `ProcessingCoordinator.process` → `TranscriptAssembler.assemble` so `TranscriptDocument.languageHint` is accurate (concrete code, or `nil` for Automatic).

**Tech Stack:** Swift 6, SwiftPM, XCTest. macOS-only app.

---

## Toolchain note (read once)

`Package.swift` declares tools-version 6.3 but the local Xcode is 6.2.4. Before any `swift build`/`swift test`, lower it; revert before every commit:

```bash
# before build/test
sed -i '' '1s/6.3/6.2/' Package.swift
# ... run build/test with: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test ...
# before commit
sed -i '' '1s/6.2/6.3/' Package.swift
```

Never commit `// swift-tools-version: 6.2`.

## File structure

- Modify: `Sources/Lorre/Core/Domain/Models.swift` — add `languageCode` to `BatchTranscriptionLanguage`.
- Modify: `Sources/Lorre/Core/Processing/TranscriptAssembler.swift` — `assemble` takes `languageHint`.
- Modify: `Sources/Lorre/Core/Processing/ProcessingCoordinator.swift` — `process` takes `languageCode`, forwards to both `assemble` calls.
- Modify: `Sources/Lorre/Features/Shell/AppViewModel.swift` — pass language code into `process`; write JSON sidecar in `performAutomaticMarkdownExportIfNeeded`.
- Modify: `Sources/Lorre/Features/Settings/GeneralSettingsTab.swift` — relabel the export section copy.
- Create: `Tests/LorreTests/BatchTranscriptionLanguageTests.swift`
- Create: `Tests/LorreTests/TranscriptAssemblerLanguageTests.swift`
- Create: `Tests/LorreTests/JSONExportEnvelopeTests.swift`

---

### Task 1: `languageCode` on `BatchTranscriptionLanguage`

**Files:**
- Modify: `Sources/Lorre/Core/Domain/Models.swift` (the `BatchTranscriptionLanguage` enum)
- Test: `Tests/LorreTests/BatchTranscriptionLanguageTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/LorreTests/BatchTranscriptionLanguageTests.swift`:

```swift
import XCTest
@testable import Lorre

final class BatchTranscriptionLanguageTests: XCTestCase {
    func testAutomaticHasNoLanguageCode() {
        XCTAssertNil(BatchTranscriptionLanguage.automatic.languageCode)
    }

    func testConcreteLanguageCodeMatchesRawValue() {
        XCTAssertEqual(BatchTranscriptionLanguage.dutch.languageCode, "nl")
        XCTAssertEqual(BatchTranscriptionLanguage.english.languageCode, "en")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
sed -i '' '1s/6.3/6.2/' Package.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter BatchTranscriptionLanguageTests
```
Expected: FAIL — `value of type 'BatchTranscriptionLanguage' has no member 'languageCode'`.

- [ ] **Step 3: Add the computed property**

In `Models.swift`, inside the `BatchTranscriptionLanguage` enum (after `shortLabel`):

```swift
    /// ASR language code for the FluidAudio hint and transcript metadata.
    /// `nil` for `.automatic` (the model detects the language itself).
    var languageCode: String? {
        self == .automatic ? nil : rawValue
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter BatchTranscriptionLanguageTests
```
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
sed -i '' '1s/6.2/6.3/' Package.swift
git add Sources/Lorre/Core/Domain/Models.swift Tests/LorreTests/BatchTranscriptionLanguageTests.swift
git commit -m "Add languageCode to BatchTranscriptionLanguage"
```

---

### Task 2: `TranscriptAssembler.assemble` stamps `languageHint`

**Files:**
- Modify: `Sources/Lorre/Core/Processing/TranscriptAssembler.swift:64-68` (signature) and `:104-109` (the `TranscriptDocument` init)
- Test: `Tests/LorreTests/TranscriptAssemblerLanguageTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/LorreTests/TranscriptAssemblerLanguageTests.swift`:

```swift
import XCTest
@testable import Lorre

final class TranscriptAssemblerLanguageTests: XCTestCase {
    private func sampleTranscription() -> TranscriptionResult {
        TranscriptionResult(
            engineName: "test",
            utterances: [
                TranscriptionUtterance(startMs: 0, endMs: 1000, text: "Hallo", confidence: nil)
            ]
        )
    }

    func testStampsProvidedLanguageHint() {
        let doc = TranscriptAssembler.assemble(
            sessionId: UUID(),
            transcription: sampleTranscription(),
            diarization: nil,
            languageHint: "nl"
        )
        XCTAssertEqual(doc.languageHint, "nl")
    }

    func testNilLanguageHintWhenOmitted() {
        let doc = TranscriptAssembler.assemble(
            sessionId: UUID(),
            transcription: sampleTranscription(),
            diarization: nil
        )
        XCTAssertNil(doc.languageHint)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
sed -i '' '1s/6.3/6.2/' Package.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter TranscriptAssemblerLanguageTests
```
Expected: FAIL — `extra argument 'languageHint' in call`.

- [ ] **Step 3: Add the parameter and pass it through**

In `TranscriptAssembler.swift`, change the signature (currently lines 64-68):

```swift
    static func assemble(
        sessionId: UUID,
        transcription: TranscriptionResult,
        diarization: DiarizationResult?,
        languageHint: String? = nil
    ) -> TranscriptDocument {
```

And change the `TranscriptDocument(...)` return (currently lines 104-109) to:

```swift
        return TranscriptDocument(
            sessionId: sessionId,
            languageHint: languageHint,
            sourceEngine: transcription.engineName,
            segments: segments,
            speakers: speakers.sorted { $0.id < $1.id }
        )
```

- [ ] **Step 4: Run test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter TranscriptAssemblerLanguageTests
```
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
sed -i '' '1s/6.2/6.3/' Package.swift
git add Sources/Lorre/Core/Processing/TranscriptAssembler.swift Tests/LorreTests/TranscriptAssemblerLanguageTests.swift
git commit -m "Let TranscriptAssembler stamp the transcript languageHint"
```

---

### Task 3: `ProcessingCoordinator.process` forwards `languageCode`

**Files:**
- Modify: `Sources/Lorre/Core/Processing/ProcessingCoordinator.swift:18-25` (signature), `:74-78` and `:120-124` (the two `assemble` calls)

No new test — this is a pass-through wired up; existing processing tests must still pass, and Task 2 covers the stamping. The new parameter has a default so existing call sites compile unchanged.

- [ ] **Step 1: Add the parameter**

Change the `process` signature (currently lines 18-25) to add `languageCode` before `onProgress`:

```swift
    func process(
        sessionId: UUID,
        enableDiarization: Bool = true,
        diarizationExpectedSpeakers: DiarizationSpeakerCountHint = .auto,
        exportDiarizationDebugArtifact: Bool = false,
        deleteAudioAfterTranscription: Bool = false,
        languageCode: String? = nil,
        onProgress: @escaping @Sendable (ProcessingUpdate) async -> Void
    ) async throws -> TranscriptDocument {
```

- [ ] **Step 2: Forward it to both `assemble` calls**

The draft-transcript call (currently lines 74-78):

```swift
                    TranscriptAssembler.assemble(
                        sessionId: sessionId,
                        transcription: transcription,
                        diarization: nil,
                        languageHint: languageCode
                    )
```

The final call (currently lines 120-124) — add the same `languageHint: languageCode` argument after its `diarization:` argument.

- [ ] **Step 3: Build to verify it compiles**

```bash
sed -i '' '1s/6.3/6.2/' Package.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build
```
Expected: Build complete.

- [ ] **Step 4: Run the full suite to confirm nothing broke**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
sed -i '' '1s/6.2/6.3/' Package.swift
git add Sources/Lorre/Core/Processing/ProcessingCoordinator.swift
git commit -m "Forward language code from ProcessingCoordinator to the assembler"
```

---

### Task 4: `AppViewModel.launchProcessing` passes the chosen language

**Files:**
- Modify: `Sources/Lorre/Features/Shell/AppViewModel.swift` (the `dependencies.processingCoordinator.process(...)` call inside `launchProcessing`)

No new test — view-model wiring is verified by build; the contract is covered by Tasks 1-2.

- [ ] **Step 1: Pass the language code into `process`**

In `launchProcessing`, the call currently reads `process(sessionId:enableDiarization:diarizationExpectedSpeakers:exportDiarizationDebugArtifact:deleteAudioAfterTranscription:onProgress:)`. Add the `languageCode` argument right before `onProgress:`:

```swift
                    deleteAudioAfterTranscription: deleteAudioAfterTranscription,
                    languageCode: self.batchTranscriptionLanguage.languageCode,
                    onProgress: { [weak self] update in
```

- [ ] **Step 2: Build to verify it compiles**

```bash
sed -i '' '1s/6.3/6.2/' Package.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build
```
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
sed -i '' '1s/6.2/6.3/' Package.swift
git add Sources/Lorre/Features/Shell/AppViewModel.swift
git commit -m "Stamp transcripts with the chosen batch language"
```

---

### Task 5: JSON envelope contract test

**Files:**
- Test: `Tests/LorreTests/JSONExportEnvelopeTests.swift`

Locks the machine contract Strongbad depends on: the JSON decodes and carries `session.id` plus the transcript segments.

- [ ] **Step 1: Write the test**

Create `Tests/LorreTests/JSONExportEnvelopeTests.swift`:

```swift
import XCTest
@testable import Lorre

final class JSONExportEnvelopeTests: XCTestCase {
    private struct Envelope: Decodable {
        let session: SessionManifest
        let transcript: TranscriptDocument
        let exportedAt: Date
    }

    func testEnvelopeCarriesSessionIdAndSegments() throws {
        let id = UUID()
        let session = SessionManifest(
            id: id,
            title: "Klantgesprek",
            status: .ready,
            recordingSource: .microphone,
            audioFileName: "audio.caf"
        )
        let transcript = TranscriptDocument(
            sessionId: id,
            languageHint: "nl",
            sourceEngine: "test",
            segments: [
                TranscriptSegment(startMs: 0, endMs: 1000, text: "Hallo", speakerId: "S1", confidence: nil)
            ],
            speakers: [SpeakerProfile.defaultProfile(id: "S1")]
        )

        let data = try MarkdownExportService().renderJSON(session: session, transcript: transcript)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: data)

        XCTAssertEqual(envelope.session.id, id)
        XCTAssertEqual(envelope.transcript.languageHint, "nl")
        XCTAssertEqual(envelope.transcript.segments.count, 1)
        XCTAssertEqual(envelope.transcript.segments.first?.text, "Hallo")
    }
}
```

- [ ] **Step 2: Run the test**

```bash
sed -i '' '1s/6.3/6.2/' Package.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter JSONExportEnvelopeTests
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
sed -i '' '1s/6.2/6.3/' Package.swift
git add Tests/LorreTests/JSONExportEnvelopeTests.swift
git commit -m "Lock the JSON export envelope contract with a test"
```

---

### Task 6: Write the JSON sidecar in automatic export

**Files:**
- Modify: `Sources/Lorre/Features/Shell/AppViewModel.swift` (`performAutomaticMarkdownExportIfNeeded`)

- [ ] **Step 1: Add the JSON sidecar write after the Markdown export**

In `performAutomaticMarkdownExportIfNeeded`, the `do { ... }` block currently creates the folder and calls `exporter.export(..., format: .markdown, destinationURL: destinationURL)`. Replace that single export with both writes and report which one fails:

```swift
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            _ = try await dependencies.exporter.export(
                session: session,
                transcript: transcript,
                format: .markdown,
                destinationURL: destinationURL
            )
            let jsonURL = destinationURL.deletingPathExtension().appendingPathExtension("json")
            _ = try await dependencies.exporter.export(
                session: session,
                transcript: transcript,
                format: .json,
                destinationURL: jsonURL
            )
            await dependencies.metrics.log(
                name: "automatic_markdown_export_succeeded",
                sessionId: sessionID,
                attributes: ["file": fileName]
            )
        } catch {
```

(The existing `catch` block stays as-is.)

- [ ] **Step 2: Build to verify it compiles**

```bash
sed -i '' '1s/6.3/6.2/' Package.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build
```
Expected: Build complete.

- [ ] **Step 3: Run the full suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
sed -i '' '1s/6.2/6.3/' Package.swift
git add Sources/Lorre/Features/Shell/AppViewModel.swift
git commit -m "Write a JSON sidecar alongside the auto-exported Markdown"
```

---

### Task 7: Update the Settings copy

**Files:**
- Modify: `Sources/Lorre/Features/Settings/GeneralSettingsTab.swift` (the "Automatic export" section)

- [ ] **Step 1: Relabel the toggle and helper text**

In the `Section("Automatic export")`, change the toggle title and helper text so it reflects both formats:

```swift
                Toggle("Save the transcript (Markdown + JSON) when it's ready", isOn: autoExportBinding)
                    .disabled(!viewModel.automaticMarkdownExport.hasFolder)
```

and the helper `Text(...)` below the template field — append a sentence:

```swift
                Text("Tokens: {date}, {time}, {datetime}, {smart_title}, {keywords}, {duration}, {speaker_count}. Preview: \(viewModel.automaticMarkdownExportFileNamePreview) (a matching .json is written alongside).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
```

- [ ] **Step 2: Build to verify it compiles**

```bash
sed -i '' '1s/6.3/6.2/' Package.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build
```
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
sed -i '' '1s/6.2/6.3/' Package.swift
git add Sources/Lorre/Features/Settings/GeneralSettingsTab.swift
git commit -m "Clarify that automatic export writes Markdown + JSON"
```

---

### Task 8: Full verification

- [ ] **Step 1: Run the complete suite**

```bash
sed -i '' '1s/6.3/6.2/' Package.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
sed -i '' '1s/6.2/6.3/' Package.swift
```
Expected: all tests pass (69 prior + 5 new = 74).

- [ ] **Step 2: Confirm tools-version is restored**

```bash
head -1 Package.swift
```
Expected: `// swift-tools-version: 6.3`.

---

## Out of scope (separate Strongbad-side specs)

- **#1 Ingest → Postgram:** rclone/rsync cron pulling the cloud folder, parsing the JSON envelope, upserting meeting entities + people links into Postgram.
- **#2 Meeting → LinkedIn:** feeding the transcript into the Acquired Taste generator.

Both consume the JSON envelope produced here.
