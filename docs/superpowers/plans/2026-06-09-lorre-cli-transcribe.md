# Lorre CLI `transcribe` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a headless `transcribe` subcommand to the existing Lorre app binary so an audio or video file can be transcribed from the command line, emitting Markdown/JSON to stdout or a file, with an optional `--register` that persists a real session and writes the auto-export envelope for the downstream pipeline.

**Architecture:** Dual-mode entrypoint (approach A). A new `@main LorreEntry` inspects `CommandLine.arguments`: a `transcribe` subcommand routes to a swift-argument-parser CLI that reuses the GUI-free core (`ProcessingCoordinator`, `FileSessionStore`, `MarkdownExportService`); anything else launches the existing SwiftUI app unchanged. Because the CLI runs inside the same signed app bundle, FluidAudio/CoreML behaves exactly as in the GUI.

**Tech Stack:** Swift 6 / SwiftPM, AVFoundation (media decode), FluidAudio (Parakeet ASR + diarization), swift-argument-parser, XCTest.

**Spec:** `docs/superpowers/specs/2026-06-09-lorre-cli-transcribe-design.md`

---

## Toolchain note (applies to every build/test step)

`Package.swift` is `swift-tools-version: 6.3` but local Xcode is 6.2.4, so **plain `swift build`/`swift test` fail**. Use:

- **Tests:** `./scripts/swift_test.sh [--filter X]` (wrapper sets `DEVELOPER_DIR`).
- **Build / run:** prefix with the Xcode toolchain, e.g.
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build`
- **Package `.app`:**
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH \
  ./scripts/package_macos_app.sh release
  ```

Never commit a tools-version change.

## File structure

- Create `Sources/Lorre/App/LorreEntry.swift` — `@main`, routes CLI vs GUI.
- Modify `Sources/Lorre/App/LorreApp.swift` — remove `@main`.
- Create `Sources/Lorre/CLI/CLIRouting.swift` — pure argv → CLI/GUI decision.
- Create `Sources/Lorre/CLI/LorreCLI.swift` — argument-parser root command.
- Create `Sources/Lorre/CLI/TranscribeCommand.swift` — the `transcribe` subcommand orchestrator.
- Create `Sources/Lorre/CLI/TranscribeServiceFactory.swift` — builds the FluidAudio core services for headless use.
- Create `Sources/Lorre/CLI/TranscribeOutputPlan.swift` — pure output-target resolution.
- Create `Sources/Lorre/Core/Support/MediaAudioImporter.swift` — AVFoundation audio/video → session audio file.
- Create `Sources/Lorre/Core/Export/AutomaticExporter.swift` — envelope (md+json) writer extracted from `AppViewModel`.
- Modify `Sources/Lorre/Features/Shell/AppViewModel.swift` — `performAutomaticMarkdownExportIfNeeded` calls `AutomaticExporter`.
- Modify `Package.swift` — add swift-argument-parser.
- Create tests under `Tests/LorreTests/`: `CLIRoutingTests.swift`, `MediaAudioImporterTests.swift`, `AutomaticExporterTests.swift`, `TranscribeOutputPlanTests.swift`.
- Create fixtures under `Tests/LorreTests/Fixtures/`: `sample-audio.m4a`, `sample-video.mp4`, `silent-video.mp4`.

---

## Task 1: Add swift-argument-parser dependency

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add the package + target dependency**

In `Package.swift`, add to `dependencies`:

```swift
.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
```

And in the `Lorre` `.executableTarget` `dependencies` array, add:

```swift
.product(name: "ArgumentParser", package: "swift-argument-parser")
```

So the target becomes:

```swift
.executableTarget(
    name: "Lorre",
    dependencies: [
        .product(name: "FluidAudio", package: "FluidAudio"),
        .product(name: "ArgumentParser", package: "swift-argument-parser")
    ]
),
```

- [ ] **Step 2: Resolve and build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build`
Expected: dependency resolves, build succeeds (no source changes yet).

- [ ] **Step 3: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "build: add swift-argument-parser dependency"
```

---

## Task 2: Entrypoint routing (CLI vs GUI)

**Files:**
- Create: `Sources/Lorre/CLI/CLIRouting.swift`
- Create: `Sources/Lorre/CLI/LorreCLI.swift`
- Create: `Sources/Lorre/CLI/TranscribeCommand.swift`
- Create: `Sources/Lorre/App/LorreEntry.swift`
- Modify: `Sources/Lorre/App/LorreApp.swift:3` (remove `@main`)
- Test: `Tests/LorreTests/CLIRoutingTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/LorreTests/CLIRoutingTests.swift`:

```swift
import XCTest
@testable import Lorre

final class CLIRoutingTests: XCTestCase {
    func testNoArgumentsLaunchesGUI() {
        XCTAssertFalse(CLIRouting.isCLIInvocation(["/Applications/Lorre.app/Contents/MacOS/Lorre"]))
    }

    func testTranscribeSubcommandIsCLI() {
        XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", "transcribe", "clip.m4a"]))
    }

    func testLaunchServicesArgumentLaunchesGUI() {
        // macOS LaunchServices can pass process-serial-number style args; must still be GUI.
        XCTAssertFalse(CLIRouting.isCLIInvocation(["/path/Lorre", "-psn_0_123456"]))
        XCTAssertFalse(CLIRouting.isCLIInvocation(["/path/Lorre", "-NSDocumentRevisionsDebugMode", "YES"]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/swift_test.sh --filter CLIRoutingTests`
Expected: FAIL — `CLIRouting` is undefined / does not compile.

- [ ] **Step 3: Implement `CLIRouting`**

Create `Sources/Lorre/CLI/CLIRouting.swift`:

```swift
import Foundation

/// Decides whether the process was launched as a CLI (a known subcommand was
/// passed) or as the normal GUI app. Only explicit subcommands count as CLI, so
/// LaunchServices-injected flags (e.g. `-psn_...`) still launch the GUI.
enum CLIRouting {
    static let subcommands: Set<String> = ["transcribe"]

    static func isCLIInvocation(_ arguments: [String]) -> Bool {
        guard let first = arguments.dropFirst().first else { return false }
        return subcommands.contains(first)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/swift_test.sh --filter CLIRoutingTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Add the CLI root + a stub transcribe command**

Create `Sources/Lorre/CLI/LorreCLI.swift`:

```swift
import ArgumentParser

struct LorreCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "Lorre",
        abstract: "Lorre local transcription CLI.",
        subcommands: [TranscribeCommand.self]
    )
}
```

Create `Sources/Lorre/CLI/TranscribeCommand.swift` (stub, fleshed out in later tasks):

```swift
import ArgumentParser
import Foundation

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio or video file locally."
    )

    @Argument(help: "Path to an audio or video file.")
    var input: String

    mutating func run() async throws {
        throw ValidationError("transcribe is not implemented yet")
    }
}
```

- [ ] **Step 6: Add the dual-mode entrypoint and remove the old `@main`**

In `Sources/Lorre/App/LorreApp.swift`, remove the `@main` attribute from `struct LorreApp` (leave the rest unchanged):

```swift
// was: @main
struct LorreApp: App {
```

Create `Sources/Lorre/App/LorreEntry.swift`:

```swift
import Foundation

@main
struct LorreEntry {
    static func main() async {
        if CLIRouting.isCLIInvocation(CommandLine.arguments) {
            await LorreCLI.main()
        } else {
            LorreApp.main()
        }
    }
}
```

- [ ] **Step 7: Build and verify GUI + CLI routing both work**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build`
Expected: build succeeds.

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run Lorre transcribe foo.m4a`
Expected: prints the validation error "transcribe is not implemented yet" and exits non-zero (does NOT open a window).

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run Lorre --help`
Expected: argument-parser help listing the `transcribe` subcommand.

(GUI launch is verified later when the bundle is packaged in Task 3.)

- [ ] **Step 8: Commit**

```bash
git add Sources/Lorre/CLI Sources/Lorre/App/LorreEntry.swift Sources/Lorre/App/LorreApp.swift Tests/LorreTests/CLIRoutingTests.swift
git commit -m "feat: dual-mode entrypoint routing CLI vs GUI"
```

---

## Task 3: Headless transcription spike (de-risk FluidAudio without GUI)

This is the gating risk from the spec: confirm FluidAudio/Parakeet loads its models and runs to completion when invoked headlessly inside the bundle, with no `NSApplication`. We implement the minimal real path (audio-only, copy input verbatim) and verify against a real speech file.

**Files:**
- Create: `Sources/Lorre/CLI/TranscribeServiceFactory.swift`
- Modify: `Sources/Lorre/CLI/TranscribeCommand.swift`

- [ ] **Step 1: Add the service factory**

Create `Sources/Lorre/CLI/TranscribeServiceFactory.swift`:

```swift
import Foundation

/// Builds the GUI-free core services the CLI needs. Mirrors the FluidAudio wiring
/// from `AppDependencies.live()` but only the transcription/diarization/export/settings
/// pieces — no recorder, playback, call watcher, or dictation.
struct TranscribeServiceFactory {
    let transcription: any TranscriptionService
    let diarization: any SpeakerDiarizationService
    let exporter: any ExportService
    let settings: AppSettingsStore

    init() {
        #if canImport(FluidAudio)
        _ = TextNormalizationRuntimeSupport.prepare()
        let enrollment = FluidAudioSpeakerEnrollmentService()
        self.transcription = FluidAudioTranscriptionService()
        self.diarization = FluidAudioDiarizationService(enrollmentService: enrollment)
        #else
        self.transcription = MockTranscriptionService()
        self.diarization = MockSpeakerDiarizationService()
        #endif
        self.exporter = MarkdownExportService()
        self.settings = AppSettingsStore()
    }
}
```

- [ ] **Step 2: Implement a minimal real `run()` (audio-only, stdout Markdown)**

Replace the body of `TranscribeCommand` in `Sources/Lorre/CLI/TranscribeCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio or video file locally."
    )

    @Argument(help: "Path to an audio or video file.")
    var input: String

    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: inputURL.path(percentEncoded: false)) else {
            throw ValidationError("Input file not found: \(input)")
        }

        let factory = TranscribeServiceFactory()
        let settings = try await factory.settings.load()

        // Spike: throwaway temp store, audio-only copy.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("lorre-cli-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = FileSessionStore(baseURL: base)
        let coordinator = ProcessingCoordinator(
            store: store,
            transcriptionService: factory.transcription,
            diarizationService: factory.diarization
        )

        let ext = sanitizedExtension(inputURL.pathExtension)
        let draft = NewSessionDraft(
            title: inputURL.deletingPathExtension().lastPathComponent,
            folderId: nil,
            status: .processing,
            durationSeconds: nil,
            recordingSource: .microphone,
            audioFileName: "audio.\(ext)",
            microphoneStemFileName: nil,
            systemAudioStemFileName: nil,
            recordedAt: Date()
        )
        let session = try await store.createSession(draft)
        let dir = await store.sessionDirectoryURL(for: session.id)
        let dest = dir.appendingPathComponent(session.audioFileName)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: inputURL, to: dest)

        await factory.diarization.setDiarizationEngine(settings.diarizationEngine)

        let transcript = try await coordinator.process(
            sessionId: session.id,
            enableDiarization: settings.isSpeakerDiarizationEnabled,
            diarizationExpectedSpeakers: settings.diarizationExpectedSpeakerCountHint,
            exportDiarizationDebugArtifact: false,
            deleteAudioAfterTranscription: false,
            languageCode: settings.batchTranscriptionLanguage.languageCode,
            onProgress: { update in
                FileHandle.standardError.write(Data("[\(Int(update.fraction * 100))%] \(update.label)\n".utf8))
            }
        )

        let reloaded = (try? await store.loadSession(id: session.id)) ?? session
        let markdown = MarkdownExportService().render(session: reloaded, transcript: transcript)
        print(markdown)
    }

    private func sanitizedExtension(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sanitized = String(lower.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        return sanitized.isEmpty ? "m4a" : sanitized
    }
}
```

- [ ] **Step 3: Build the app bundle**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH \
./scripts/package_macos_app.sh release
```
Expected: `dist/Lorre.app` is produced.

- [ ] **Step 4: VERIFY headless transcription (the gating check)**

Run against a real speech file (use the morning's extract; it has speech):
```bash
./dist/Lorre.app/Contents/MacOS/Lorre transcribe "$HOME/Downloads/Thijs Leufkens - Proposal Walkthrough.m4a"
```
Expected: progress lines on stderr, then a Markdown transcript with real words on stdout. **No window opens.** Exit code 0.

If this fails because models/ANE do not load headlessly, STOP — the dual-mode-in-bundle assumption is wrong; reconsider approach B (separate target) with the team before continuing.

- [ ] **Step 5: VERIFY GUI still launches**

Run: `open ./dist/Lorre.app`
Expected: the normal Lorre window opens (no-args path unaffected). Quit it.

- [ ] **Step 6: Commit**

```bash
git add Sources/Lorre/CLI/TranscribeServiceFactory.swift Sources/Lorre/CLI/TranscribeCommand.swift
git commit -m "feat: minimal headless transcribe (audio-only) + factory"
```

---

## Task 4: Test fixtures (audio + video)

**Files:**
- Create: `Tests/LorreTests/Fixtures/sample-audio.m4a`
- Create: `Tests/LorreTests/Fixtures/sample-video.mp4`
- Create: `Tests/LorreTests/Fixtures/silent-video.mp4`

- [ ] **Step 1: Generate small fixtures with ffmpeg**

Run from the repo root:
```bash
cd "Tests/LorreTests/Fixtures"
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=2" -c:a aac sample-audio.m4a
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=2" -f lavfi -i "color=c=black:s=64x64:d=2" -shortest -c:v libx264 -c:a aac sample-video.mp4
ffmpeg -y -f lavfi -i "color=c=black:s=64x64:d=2" -c:v libx264 -an silent-video.mp4
cd -
```
Expected: three small files created (each well under 100 KB).

- [ ] **Step 2: Confirm they are valid and have the expected tracks**

Run:
```bash
ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "Tests/LorreTests/Fixtures/sample-video.mp4"
ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "Tests/LorreTests/Fixtures/silent-video.mp4"
```
Expected: `sample-video.mp4` lists both `video` and `audio`; `silent-video.mp4` lists only `video`.

- [ ] **Step 3: Commit**

```bash
git add Tests/LorreTests/Fixtures/sample-audio.m4a Tests/LorreTests/Fixtures/sample-video.mp4 Tests/LorreTests/Fixtures/silent-video.mp4
git commit -m "test: add audio/video fixtures for media importer"
```

---

## Task 5: `MediaAudioImporter` (audio + video input)

**Files:**
- Create: `Sources/Lorre/Core/Support/MediaAudioImporter.swift`
- Modify: `Sources/Lorre/CLI/TranscribeCommand.swift` (replace inline copy)
- Test: `Tests/LorreTests/MediaAudioImporterTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/LorreTests/MediaAudioImporterTests.swift`:

```swift
import AVFoundation
import XCTest
@testable import Lorre

final class MediaAudioImporterTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mai-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testCopiesAudioOnlyInputVerbatim() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = try await MediaAudioImporter.prepareAudio(from: fixtureURL("sample-audio.m4a"), intoDirectory: dir)
        XCTAssertEqual(name, "audio.m4a")
        let out = dir.appendingPathComponent(name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path(percentEncoded: false)))
        let file = try AVAudioFile(forReading: out)
        XCTAssertGreaterThan(file.length, 0)
    }

    func testExtractsAudioFromVideoToM4A() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = try await MediaAudioImporter.prepareAudio(from: fixtureURL("sample-video.mp4"), intoDirectory: dir)
        XCTAssertEqual(name, "audio.m4a")
        let out = dir.appendingPathComponent(name)
        let file = try AVAudioFile(forReading: out)
        XCTAssertGreaterThan(file.length, 0)
    }

    func testThrowsWhenNoAudioTrack() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            _ = try await MediaAudioImporter.prepareAudio(from: fixtureURL("silent-video.mp4"), intoDirectory: dir)
            XCTFail("expected noAudioTrack")
        } catch let error as MediaAudioImporter.ImportError {
            XCTAssertEqual(error, .noAudioTrack)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/swift_test.sh --filter MediaAudioImporterTests`
Expected: FAIL — `MediaAudioImporter` undefined.

- [ ] **Step 3: Implement `MediaAudioImporter`**

Create `Sources/Lorre/Core/Support/MediaAudioImporter.swift`:

```swift
import AVFoundation
import Foundation

/// Prepares an arbitrary media file for the transcription pipeline by writing an
/// audio file into a session directory. Audio-only inputs are copied verbatim;
/// inputs that also contain video have their audio track extracted to `audio.m4a`.
enum MediaAudioImporter {
    enum ImportError: Error, Equatable {
        case noAudioTrack
        case exportFailed(String)
    }

    /// Returns the file name written into `directory` (store it as `audioFileName`).
    static func prepareAudio(from sourceURL: URL, intoDirectory directory: URL) async throws -> String {
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw ImportError.noAudioTrack }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if videoTracks.isEmpty {
            let fileName = "audio.\(sanitizedExtension(sourceURL.pathExtension))"
            let dest = directory.appendingPathComponent(fileName)
            try removeIfExists(dest)
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return fileName
        }

        let fileName = "audio.m4a"
        let dest = directory.appendingPathComponent(fileName)
        try removeIfExists(dest)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ImportError.exportFailed("Could not create AVAssetExportSession")
        }
        do {
            try await export.export(to: dest, as: .m4a)
        } catch {
            throw ImportError.exportFailed(error.localizedDescription)
        }
        return fileName
    }

    private static func removeIfExists(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func sanitizedExtension(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sanitized = String(lower.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        return sanitized.isEmpty ? "m4a" : sanitized
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/swift_test.sh --filter MediaAudioImporterTests`
Expected: PASS (3 tests).

Note: `AVAssetExportSession.export(to:as:)` is macOS 15+ async API; the deployment target is macOS 15, so it is available.

- [ ] **Step 5: Use the importer in `TranscribeCommand`**

In `Sources/Lorre/CLI/TranscribeCommand.swift`, replace the extension/draft/copy block (from `let ext = sanitizedExtension(...)` through the `copyItem` line) with:

```swift
let draft = NewSessionDraft(
    title: inputURL.deletingPathExtension().lastPathComponent,
    folderId: nil,
    status: .processing,
    durationSeconds: nil,
    recordingSource: .microphone,
    audioFileName: "audio.m4a",
    microphoneStemFileName: nil,
    systemAudioStemFileName: nil,
    recordedAt: Date()
)
var session = try await store.createSession(draft)
let dir = await store.sessionDirectoryURL(for: session.id)
let audioFileName = try await MediaAudioImporter.prepareAudio(from: inputURL, intoDirectory: dir)
if audioFileName != session.audioFileName {
    session.audioFileName = audioFileName
    session.updatedAt = Date()
    try await store.updateSession(session)
}
```

Then delete the now-unused private `sanitizedExtension(_:)` from `TranscribeCommand` (it lives in `MediaAudioImporter` now). Update the later `store.loadSession` line to keep using `session.id`.

- [ ] **Step 6: Build and verify mp4 works headless**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build`
Expected: build succeeds.

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run Lorre transcribe "$HOME/Downloads/Thijs Leufkens - Proposal Walkthrough.mp4"`
Expected: transcript on stdout (the .mp4 is decoded directly — no ffmpeg step).

- [ ] **Step 7: Commit**

```bash
git add Sources/Lorre/Core/Support/MediaAudioImporter.swift Sources/Lorre/CLI/TranscribeCommand.swift Tests/LorreTests/MediaAudioImporterTests.swift
git commit -m "feat: MediaAudioImporter decodes audio + video for the CLI"
```

---

## Task 6: Extract `AutomaticExporter` into Core

**Files:**
- Create: `Sources/Lorre/Core/Export/AutomaticExporter.swift`
- Modify: `Sources/Lorre/Features/Shell/AppViewModel.swift` (`performAutomaticMarkdownExportIfNeeded`)
- Test: `Tests/LorreTests/AutomaticExporterTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/LorreTests/AutomaticExporterTests.swift`:

```swift
import Foundation
import XCTest
@testable import Lorre

final class AutomaticExporterTests: XCTestCase {
    private func decodeFixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    func testWritesMarkdownAndJSONEnvelope() async throws {
        let session = try decodeFixture(SessionManifest.self, "session-manifest-v1-with-version.json")
        let transcript = try decodeFixture(TranscriptDocument.self, "transcript-document-v1.json")
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ae-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = AutomaticMarkdownExportConfiguration(
            isEnabled: true,
            folderPath: folder.path(percentEncoded: false),
            fileNameTemplate: AutomaticMarkdownExportConfiguration.defaultFileNameTemplate
        )

        let result = try await AutomaticExporter.writeEnvelope(
            session: session,
            transcript: transcript,
            configuration: config,
            exporter: MarkdownExportService()
        )

        XCTAssertEqual(result.markdown.pathExtension, "md")
        XCTAssertEqual(result.json.pathExtension, "json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.markdown.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.json.path(percentEncoded: false)))

        // JSON must be the {session, transcript, exportedAt} envelope lorre-ingest expects.
        let data = try Data(contentsOf: result.json)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["session"])
        XCTAssertNotNil(object?["transcript"])
        XCTAssertNotNil(object?["exportedAt"])
    }

    func testThrowsWhenNoFolderConfigured() async throws {
        let session = try decodeFixture(SessionManifest.self, "session-manifest-v1-with-version.json")
        let transcript = try decodeFixture(TranscriptDocument.self, "transcript-document-v1.json")
        let config = AutomaticMarkdownExportConfiguration(isEnabled: false, folderPath: nil)
        do {
            _ = try await AutomaticExporter.writeEnvelope(
                session: session, transcript: transcript, configuration: config, exporter: MarkdownExportService()
            )
            XCTFail("expected noFolder")
        } catch let error as AutomaticExporter.ExportError {
            XCTAssertEqual(error, .noFolder)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/swift_test.sh --filter AutomaticExporterTests`
Expected: FAIL — `AutomaticExporter` undefined.

- [ ] **Step 3: Implement `AutomaticExporter`**

Create `Sources/Lorre/Core/Export/AutomaticExporter.swift`:

```swift
import Foundation

/// Writes the finalized transcript as the `.md` + `.json` envelope into the
/// configured auto-export folder. Single source of truth for the envelope contract
/// consumed by `strongbad-lorre-ingest`; used by both the GUI auto-export and the CLI.
enum AutomaticExporter {
    enum ExportError: Error, Equatable {
        case noFolder
    }

    @discardableResult
    static func writeEnvelope(
        session: SessionManifest,
        transcript: TranscriptDocument,
        configuration: AutomaticMarkdownExportConfiguration,
        exporter: any ExportService
    ) async throws -> (markdown: URL, json: URL) {
        guard let folderURL = configuration.folderURL else { throw ExportError.noFolder }

        let fileName = AutomaticExportFileNameBuilder.fileName(
            session: session,
            transcript: transcript,
            template: configuration.fileNameTemplate
        )
        let markdownURL = folderURL.appendingPathComponent(fileName)
        let jsonURL = markdownURL.deletingPathExtension().appendingPathExtension("json")

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        _ = try await exporter.export(session: session, transcript: transcript, format: .markdown, destinationURL: markdownURL)
        _ = try await exporter.export(session: session, transcript: transcript, format: .json, destinationURL: jsonURL)
        return (markdownURL, jsonURL)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/swift_test.sh --filter AutomaticExporterTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Refactor `AppViewModel.performAutomaticMarkdownExportIfNeeded` to use it**

In `Sources/Lorre/Features/Shell/AppViewModel.swift`, replace the body of `performAutomaticMarkdownExportIfNeeded` so the file-naming + md + json writes go through `AutomaticExporter`, keeping the existing metrics + banner behavior:

```swift
private func performAutomaticMarkdownExportIfNeeded(sessionID: UUID, transcript: TranscriptDocument) async {
    let configuration = automaticMarkdownExport
    guard configuration.isEnabled, configuration.folderURL != nil else { return }
    guard let session = try? await dependencies.store.loadSession(id: sessionID) else { return }

    do {
        let result = try await AutomaticExporter.writeEnvelope(
            session: session,
            transcript: transcript,
            configuration: configuration,
            exporter: dependencies.exporter
        )
        await dependencies.metrics.log(
            name: "automatic_markdown_export_succeeded",
            sessionId: sessionID,
            attributes: ["file": result.markdown.lastPathComponent]
        )
    } catch {
        await dependencies.metrics.log(
            name: "automatic_markdown_export_failed",
            sessionId: sessionID,
            attributes: ["error": error.localizedDescription]
        )
        await MainActor.run {
            self.banner = AppBanner(
                kind: .error,
                title: "Automatic export failed",
                message: "Could not write to \(configuration.folderDisplayName). \(error.localizedDescription)"
            )
        }
    }
}
```

- [ ] **Step 6: Run the full suite to confirm no regression**

Run: `./scripts/swift_test.sh`
Expected: all tests pass (existing suite + the new ones).

- [ ] **Step 7: Commit**

```bash
git add Sources/Lorre/Core/Export/AutomaticExporter.swift Sources/Lorre/Features/Shell/AppViewModel.swift Tests/LorreTests/AutomaticExporterTests.swift
git commit -m "refactor: extract AutomaticExporter into Core, reuse in GUI"
```

---

## Task 7: Full flag surface + output planning

**Files:**
- Create: `Sources/Lorre/CLI/TranscribeOutputPlan.swift`
- Modify: `Sources/Lorre/CLI/TranscribeCommand.swift`
- Test: `Tests/LorreTests/TranscribeOutputPlanTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/LorreTests/TranscribeOutputPlanTests.swift`:

```swift
import Foundation
import XCTest
@testable import Lorre

final class TranscribeOutputPlanTests: XCTestCase {
    func testMarkdownToStdoutWhenNoOut() throws {
        XCTAssertEqual(try TranscribeOutputPlan.resolve(format: .md, out: nil), .stdout(.markdown))
    }

    func testJSONToStdoutWhenNoOut() throws {
        XCTAssertEqual(try TranscribeOutputPlan.resolve(format: .json, out: nil), .stdout(.json))
    }

    func testSingleFileWhenOutGiven() throws {
        let plan = try TranscribeOutputPlan.resolve(format: .md, out: "/tmp/x.md")
        XCTAssertEqual(plan, .file(URL(fileURLWithPath: "/tmp/x.md"), .markdown))
    }

    func testBothRequiresOut() {
        XCTAssertThrowsError(try TranscribeOutputPlan.resolve(format: .both, out: nil))
    }

    func testBothProducesMarkdownAndJSONPair() throws {
        let plan = try TranscribeOutputPlan.resolve(format: .both, out: "/tmp/walkthrough")
        XCTAssertEqual(plan, .pair(
            markdown: URL(fileURLWithPath: "/tmp/walkthrough.md"),
            json: URL(fileURLWithPath: "/tmp/walkthrough.json")
        ))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/swift_test.sh --filter TranscribeOutputPlanTests`
Expected: FAIL — `TranscribeOutputPlan` / `TranscribeFormat` undefined.

- [ ] **Step 3: Implement the output plan + format enum**

Create `Sources/Lorre/CLI/TranscribeOutputPlan.swift`:

```swift
import ArgumentParser
import Foundation

enum TranscribeFormat: String, ExpressibleByArgument, CaseIterable {
    case md
    case json
    case both
}

/// Pure resolution of where rendered output goes, independent of ArgumentParser/FluidAudio.
enum TranscribeOutputPlan: Equatable {
    case stdout(ExportFormat)
    case file(URL, ExportFormat)
    case pair(markdown: URL, json: URL)

    static func resolve(format: TranscribeFormat, out: String?) throws -> TranscribeOutputPlan {
        switch format {
        case .md:
            guard let out else { return .stdout(.markdown) }
            return .file(URL(fileURLWithPath: out), .markdown)
        case .json:
            guard let out else { return .stdout(.json) }
            return .file(URL(fileURLWithPath: out), .json)
        case .both:
            guard let out else {
                throw ValidationError("--format both requires --out <stem> (writes <stem>.md and <stem>.json)")
            }
            let stem = URL(fileURLWithPath: out)
            return .pair(
                markdown: stem.deletingPathExtension().appendingPathExtension("md"),
                json: stem.deletingPathExtension().appendingPathExtension("json")
            )
        }
    }
}
```

Note: for `both`, `out` is treated as a stem — a trailing `.md`/`.json` is stripped via `deletingPathExtension()` so `--out walkthrough` and `--out walkthrough.md` both yield `walkthrough.md` + `walkthrough.json`.

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/swift_test.sh --filter TranscribeOutputPlanTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Wire the full flag surface into `TranscribeCommand`**

Replace `Sources/Lorre/CLI/TranscribeCommand.swift` with the complete version:

```swift
import ArgumentParser
import Foundation

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio or video file locally."
    )

    @Argument(help: "Path to an audio or video file.")
    var input: String

    @Option(name: [.short, .long], help: "Output path. Omit to write to stdout. For --format both this is a path stem.")
    var out: String?

    @Option(help: "Output format: md, json, or both.")
    var format: TranscribeFormat = .md

    @Flag(help: "Persist a real Lorre session and write the md+json auto-export envelope for the downstream pipeline.")
    var register: Bool = false

    @Option(help: "Export folder for --register (overrides the folder configured in Lorre settings).")
    var exportDir: String?

    @Option(help: "ASR language code (e.g. nl, en). Omit for automatic detection.")
    var language: String?

    @Flag(inversion: .prefixedNo, help: "Enable/disable speaker diarization. Defaults to the Lorre setting.")
    var diarization: Bool?

    @Option(help: "Expected speaker count hint.")
    var speakers: Int?

    @Flag(help: "Suppress progress output on stderr.")
    var quiet: Bool = false

    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: inputURL.path(percentEncoded: false)) else {
            throw ValidationError("Input file not found: \(input)")
        }
        let outputPlan = try TranscribeOutputPlan.resolve(format: format, out: out)

        let factory = TranscribeServiceFactory()
        let settings = try await factory.settings.load()

        // Store: real default base when registering, throwaway temp otherwise.
        let store: FileSessionStore
        var tempBase: URL?
        if register {
            store = FileSessionStore()
        } else {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("lorre-cli-\(UUID().uuidString)", isDirectory: true)
            tempBase = base
            store = FileSessionStore(baseURL: base)
        }
        defer { if let tempBase { try? FileManager.default.removeItem(at: tempBase) } }

        let coordinator = ProcessingCoordinator(
            store: store,
            transcriptionService: factory.transcription,
            diarizationService: factory.diarization
        )

        // Create the session and import audio (audio passthrough or video extraction).
        let draft = NewSessionDraft(
            title: inputURL.deletingPathExtension().lastPathComponent,
            folderId: nil,
            status: .processing,
            durationSeconds: nil,
            recordingSource: .microphone,
            audioFileName: "audio.m4a",
            microphoneStemFileName: nil,
            systemAudioStemFileName: nil,
            recordedAt: Date()
        )
        var session = try await store.createSession(draft)
        let dir = await store.sessionDirectoryURL(for: session.id)
        let audioFileName = try await MediaAudioImporter.prepareAudio(from: inputURL, intoDirectory: dir)
        if audioFileName != session.audioFileName {
            session.audioFileName = audioFileName
            session.updatedAt = Date()
            try await store.updateSession(session)
        }

        // Diarization / language resolution: flags override settings.
        await factory.diarization.setDiarizationEngine(settings.diarizationEngine)
        let enableDiarization = diarization ?? settings.isSpeakerDiarizationEnabled
        let speakerHint: DiarizationSpeakerCountHint = speakers.map { .exact($0) } ?? settings.diarizationExpectedSpeakerCountHint
        let languageCode = language ?? settings.batchTranscriptionLanguage.languageCode

        let transcript = try await coordinator.process(
            sessionId: session.id,
            enableDiarization: enableDiarization,
            diarizationExpectedSpeakers: speakerHint,
            exportDiarizationDebugArtifact: false,
            deleteAudioAfterTranscription: false,
            languageCode: languageCode,
            onProgress: { [quiet] update in
                guard !quiet else { return }
                FileHandle.standardError.write(Data("[\(Int(update.fraction * 100))%] \(update.label)\n".utf8))
            }
        )

        let reloaded = (try? await store.loadSession(id: session.id)) ?? session
        let renderer = MarkdownExportService()

        try emit(plan: outputPlan, session: reloaded, transcript: transcript, renderer: renderer)

        if register {
            let configuration = registerExportConfiguration(settings: settings)
            guard configuration.folderURL != nil else {
                throw ValidationError("--register needs an export folder. Set one in Lorre settings or pass --export-dir <path>.")
            }
            let result = try await AutomaticExporter.writeEnvelope(
                session: reloaded, transcript: transcript, configuration: configuration, exporter: renderer
            )
            if !quiet {
                FileHandle.standardError.write(Data("Registered session \(reloaded.id) → \(result.json.lastPathComponent)\n".utf8))
            }
        }
    }

    private func registerExportConfiguration(settings: AppSettings) -> AutomaticMarkdownExportConfiguration {
        guard let exportDir else { return settings.automaticMarkdownExport }
        return AutomaticMarkdownExportConfiguration(
            isEnabled: true,
            folderPath: exportDir,
            fileNameTemplate: settings.automaticMarkdownExport.fileNameTemplate
        )
    }

    private func emit(
        plan: TranscribeOutputPlan,
        session: SessionManifest,
        transcript: TranscriptDocument,
        renderer: MarkdownExportService
    ) throws {
        switch plan {
        case .stdout(.markdown):
            print(renderer.render(session: session, transcript: transcript))
        case .stdout(.json):
            FileHandle.standardOutput.write(try renderer.renderJSON(session: session, transcript: transcript))
        case .stdout(.plainText):
            print(renderer.renderPlainText(session: session, transcript: transcript))
        case let .file(url, .markdown):
            try Data(renderer.render(session: session, transcript: transcript).utf8).write(to: url)
        case let .file(url, .plainText):
            try Data(renderer.renderPlainText(session: session, transcript: transcript).utf8).write(to: url)
        case let .file(url, .json):
            try renderer.renderJSON(session: session, transcript: transcript).write(to: url)
        case let .pair(markdownURL, jsonURL):
            try Data(renderer.render(session: session, transcript: transcript).utf8).write(to: markdownURL)
            try renderer.renderJSON(session: session, transcript: transcript).write(to: jsonURL)
        }
    }
}
```

- [ ] **Step 6: Build + full suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build`
Expected: build succeeds.

Run: `./scripts/swift_test.sh`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Lorre/CLI/TranscribeOutputPlan.swift Sources/Lorre/CLI/TranscribeCommand.swift Tests/LorreTests/TranscribeOutputPlanTests.swift
git commit -m "feat: full transcribe flag surface + output planning"
```

---

## Task 8: Manual integration matrix

No code; verifies the end-to-end behaviour against real media.

**Files:** none.

- [ ] **Step 1: Repackage and install the bundle**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH \
./scripts/package_macos_app.sh release
rm -rf /Applications/Lorre.app && cp -R dist/Lorre.app /Applications/
```
Expected: succeeds.

- [ ] **Step 2: Headless transcript to stdout (no library entry)**

Run: `/Applications/Lorre.app/Contents/MacOS/Lorre transcribe "$HOME/Downloads/Thijs Leufkens - Proposal Walkthrough.mp4"`
Expected: Markdown transcript on stdout; nothing added to the Lorre library (open the app to confirm no new session).

- [ ] **Step 3: JSON + file output**

Run: `/Applications/Lorre.app/Contents/MacOS/Lorre transcribe "$HOME/Downloads/Thijs Leufkens - Proposal Walkthrough.m4a" --format both -o /tmp/walkthrough`
Expected: `/tmp/walkthrough.md` and `/tmp/walkthrough.json` exist; the JSON is the `{session, transcript, exportedAt}` envelope.

- [ ] **Step 4: `--register` round-trip**

Ensure an export folder is configured (Lorre → Settings → auto-export) or pass `--export-dir`. Run:
```bash
/Applications/Lorre.app/Contents/MacOS/Lorre transcribe "$HOME/Downloads/Thijs Leufkens - Proposal Walkthrough.m4a" --register --export-dir /tmp/lorre-export
```
Expected: `/tmp/lorre-export/<date>-<title>.md` + `.json` written; a new session appears in `~/Library/Application Support/Lorre/sessions/` (and in the GUI after relaunch).

- [ ] **Step 5: Confirm GUI unaffected**

Run: `open /Applications/Lorre.app`
Expected: normal window; recording/import still work. Quit.

- [ ] **Step 6 (no commit — verification only).** Record results in the PR description.

---

## Task 9: Documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Document the CLI in README**

Under "Key features" / a new "Command line" section in `README.md`, add:

```markdown
## Command line

The app binary doubles as a headless CLI. Inside the bundle:

    /Applications/Lorre.app/Contents/MacOS/Lorre transcribe <file> [options]

- Accepts audio or video (mp4/mov/m4a/wav/mp3 …); video audio tracks are extracted automatically.
- `--out <path>` / `-o` writes to a file (default: stdout). `--format md|json|both` (`both` requires `--out`, treated as a path stem).
- `--register` persists the file as a real Lorre session and writes the md+json auto-export envelope to the configured folder (or `--export-dir <path>`), so the downstream ingest pipeline picks it up.
- `--language <code>`, `--no-diarization`, `--speakers <n>`, `--quiet` mirror the in-app settings.
```

- [ ] **Step 2: Document in CLAUDE.md**

Add a row to the "Common commands" table in `CLAUDE.md`:

```markdown
| Transcribe headless | `dist/Lorre.app/Contents/MacOS/Lorre transcribe <file> [--register]` |
```

And a short note in the architecture/layout section that `Sources/Lorre/CLI/` holds the dual-mode CLI, entered via `LorreEntry` (`App/LorreEntry.swift`) which routes to either `LorreCLI` or the SwiftUI `LorreApp` based on `CLIRouting`.

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document the headless transcribe CLI"
```

---

## Self-review notes

- **Spec coverage:** entrypoint (§1)→Task 2; CLI surface (§2)→Tasks 3/7; audio+video input (§3)→Task 5; transcription flow incl. temp-vs-default store (§4)→Tasks 3/7; AutomaticExporter refactor (§5)→Task 6; app-state-sync caveat (§6)→Task 8 step 4 note; testing (§7)→Tasks 4–7; FluidAudio spike (risk)→Task 3.
- **Store/registration:** with `--register` the session is created in the default `FileSessionStore` base (= app library) by construction, satisfying "also in GUI library"; the envelope write satisfies downstream pickup.
- **Type consistency check:** `MediaAudioImporter.prepareAudio(from:intoDirectory:)`, `AutomaticExporter.writeEnvelope(session:transcript:configuration:exporter:)`, `TranscribeOutputPlan.resolve(format:out:)`, `TranscribeFormat`, and `ProcessingCoordinator.process(sessionId:enableDiarization:diarizationExpectedSpeakers:exportDiarizationDebugArtifact:deleteAudioAfterTranscription:languageCode:onProgress:)` are used identically across tasks. `DiarizationSpeakerCountHint.exact(_:)` and `.auto` are both confirmed present (used in `tuningPresets`). `AppSettings` fields used: `diarizationEngine`, `isSpeakerDiarizationEnabled`, `diarizationExpectedSpeakerCountHint`, `batchTranscriptionLanguage.languageCode`, `automaticMarkdownExport`.
