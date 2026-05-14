# Recorder + Settings Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all per-app preferences out of the Recorder main pane into a native SwiftUI `Settings` scene (CMD+,) with 4 tabs; reduce the Recorder pane to a minimal hero; relocate source-mode selection to the window toolbar.

**Architecture:** Add a `Settings` scene next to the existing `WindowGroup` in `LorreApp.swift`. Inside `Settings`, a 4-tab `TabView`: General, Speech & Models, Speakers, About — each a SwiftUI `Form`. Settings tabs bind directly to the shared `AppViewModel.appSettings` so changes persist via the existing `AppSettingsStore`. The Recorder pane is stripped to: kicker, hero title, big Start button, two-line status. Source-mode segmented control + gear icon move to `.toolbar { }` on the window. The italic-serif `LorreWordmark` leaves the sidebar (window title carries the app name) and survives in the About tab.

**Tech Stack:** SwiftUI (macOS 14+), `Settings` scene, `Form`, XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-14-recorder-settings-restructure.md`

**Branch:** `claude/apple-native-recorder` (already created; spec already committed)

---

## Toolchain note

Package requires `swift-tools-version: 6.3`; locally only Xcode 6.2.4 is installed. For all build/test commands below:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift {build|test}
```

If 6.3 is still required, temporarily set `Package.swift` line 1 to `// swift-tools-version: 6.2`, build/test, then **revert before committing**. Do not commit Package.swift changes.

---

## Out-of-spec decision

The spec mentions a "Language hint for transcription" picker in the General tab and flagged it as needing either an existing or new `AppSettings.languageHint` field. After verification: `AppSettings` does **not** have a `languageHint` field (only `TranscriptDocument.languageHint` exists, per-document). Adding a new global preference is out of scope for this UI restructure (YAGNI).

**This plan omits the language picker from the General tab.** The user can decide later whether to add a global language preference as its own sub-project. General tab will have: Audio (retention) + Live transcription (live preview). Nothing else.

---

## Task 1: Settings scene scaffold + CMD+, wiring

**Files:**
- Create: `Sources/Lorre/Features/Settings/SettingsView.swift`
- Modify: `Sources/Lorre/App/LorreApp.swift`

- [ ] **Step 1: Read `LorreApp.swift`**

Read `Sources/Lorre/App/LorreApp.swift`. Note that `viewModel` is a `@StateObject` on `LorreApp`. The shared `viewModel` instance must be injected into the new Settings scene.

- [ ] **Step 2: Create the SettingsView scaffold**

Create `Sources/Lorre/Features/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            GeneralSettingsTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }
            SpeechModelsSettingsTab(viewModel: viewModel)
                .tabItem { Label("Speech & Models", systemImage: "waveform.and.mic") }
            SpeakersSettingsTab(viewModel: viewModel)
                .tabItem { Label("Speakers", systemImage: "person.2") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540)
        .frame(minHeight: 380)
    }
}

// Placeholder stubs — replaced by dedicated files in later tasks.
private struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View { Form { Text("General — placeholder") }.formStyle(.grouped) }
}
private struct SpeechModelsSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View { Form { Text("Speech & Models — placeholder") }.formStyle(.grouped) }
}
private struct SpeakersSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View { Form { Text("Speakers — placeholder") }.formStyle(.grouped) }
}
private struct AboutSettingsTab: View {
    var body: some View { Form { Text("About — placeholder") }.formStyle(.grouped) }
}
```

Note: the `private struct` placeholders here will be **moved out** to their own files in Tasks 2–5. Each later task removes one `private struct` from this file and creates the corresponding standalone file. Done this way to keep CMD+, wiring testable from Task 1.

- [ ] **Step 3: Add the Settings scene to LorreApp**

Edit `Sources/Lorre/App/LorreApp.swift`. The current body has just `WindowGroup`. Add a `Settings` scene that shares the same `viewModel`:

```swift
import SwiftUI

@main
struct LorreApp: App {
    @StateObject private var viewModel = AppViewModel(dependencies: .live())

    var body: some Scene {
        WindowGroup("Lorre") {
            AppShellView(viewModel: viewModel)
                .frame(minWidth: 1120, minHeight: 760)
                .preferredColorScheme(nil)
                .task {
                    await viewModel.start()
                }
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
```

The `Settings { }` scene automatically wires CMD+, and the "Lorre > Settings…" menu item.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build complete with no errors.

- [ ] **Step 5: Smoke test CMD+,**

Build the .app via `./scripts/package_macos_app.sh release` (or use the existing dist build if unchanged) and launch. Press CMD+,. Expected: a new window opens titled "Lorre Settings" with 4 placeholder tabs.

(This is a manual verification step. If the engineer is running in a headless context, they can skip the visual check and trust the build.)

- [ ] **Step 6: Commit**

```bash
git add Sources/Lorre/Features/Settings/SettingsView.swift Sources/Lorre/App/LorreApp.swift
git commit -m "Scaffold Settings scene with 4-tab placeholder structure"
```

---

## Task 2: GeneralSettingsTab

**Files:**
- Create: `Sources/Lorre/Features/Settings/GeneralSettingsTab.swift`
- Modify: `Sources/Lorre/Features/Settings/SettingsView.swift` (remove the inline `GeneralSettingsTab` stub)

- [ ] **Step 1: Read existing AppSettings bindings**

The relevant bindings come from `AppViewModel`. They expose `viewModel.appSettings.isDeleteAudioAfterTranscriptionEnabled: Bool` and `viewModel.appSettings.isLiveTranscriptionEnabled: Bool`. To bind in SwiftUI, use a custom `Binding` that reads from `viewModel.appSettings` and writes via the existing setter — or use the existing convenience setters on `AppViewModel` if any exist.

Open `Sources/Lorre/Features/Shell/AppViewModel.swift` and search for how the current Recorder UI updates these fields. There should be either:
- Direct `Binding(get:set:)` patterns where the UI sets `viewModel.appSettings.isLiveTranscriptionEnabled = ...`
- OR a typed setter method like `viewModel.setLiveTranscriptionEnabled(_ enabled: Bool)`

Use whichever pattern is already in use. Be consistent with how the existing Recorder pane writes to these settings.

- [ ] **Step 2: Create `GeneralSettingsTab.swift`**

Create `Sources/Lorre/Features/Settings/GeneralSettingsTab.swift`:

```swift
import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Audio") {
                Picker("Source audio after transcript", selection: retentionBinding) {
                    Text("Keep audio").tag(false)
                    Text("Delete after transcript").tag(true)
                }
                .pickerStyle(.segmented)
                Text("Keep the audio file alongside the transcript, or auto-delete it once transcription completes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Live transcription") {
                Toggle("Show live preview while recording", isOn: liveTranscriptionBinding)
                Text("Streams partial transcript text as you speak. Uses a faster, lower-accuracy model.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private var retentionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.appSettings.isDeleteAudioAfterTranscriptionEnabled },
            set: { viewModel.appSettings.isDeleteAudioAfterTranscriptionEnabled = $0 }
        )
    }

    private var liveTranscriptionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.appSettings.isLiveTranscriptionEnabled },
            set: { viewModel.appSettings.isLiveTranscriptionEnabled = $0 }
        )
    }
}
```

**If the existing Recorder pane uses typed setter methods on `AppViewModel`** (e.g., `viewModel.setLiveTranscriptionEnabled(_:)`), replace the direct property writes in the Binding `set:` closures with the setter calls. Persistence behavior must match exactly what the Recorder pane does today.

- [ ] **Step 3: Update `SettingsView.swift` to remove the inline stub**

Edit `Sources/Lorre/Features/Settings/SettingsView.swift` and delete the entire `private struct GeneralSettingsTab` block. Keep the other three placeholder stubs for now.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: clean build.

- [ ] **Step 5: Manual smoke test**

Build + launch the app. Open CMD+,. The General tab should show:
- Audio section with a segmented picker (Keep audio / Delete after transcript)
- Live transcription section with a toggle and helper text
- Default values reflect current `AppSettings`

Toggle each control and verify it persists (close + reopen Settings; values stick).

- [ ] **Step 6: Commit**

```bash
git add Sources/Lorre/Features/Settings/GeneralSettingsTab.swift Sources/Lorre/Features/Settings/SettingsView.swift
git commit -m "Add GeneralSettingsTab (retention + live preview)"
```

---

## Task 3: SpeechModelsSettingsTab

**Files:**
- Create: `Sources/Lorre/Features/Settings/SpeechModelsSettingsTab.swift`
- Modify: `Sources/Lorre/Features/Settings/SettingsView.swift` (remove the inline `SpeechModelsSettingsTab` stub)

- [ ] **Step 1: Read the existing model settings UI**

Open `Sources/Lorre/Features/Shell/SessionShelfModelSettingsView.swift`. This file currently hosts the model preparation panel, diarization mode picker, diarization engine picker, expected-speakers picker, and model registry. Identify each Picker / Toggle binding and the corresponding `viewModel` property.

- [ ] **Step 2: Create `SpeechModelsSettingsTab.swift`**

Migrate the bindings into a Form-based layout. Use the **same** view model methods/properties as the existing view — do NOT invent new ones.

```swift
import SwiftUI

struct SpeechModelsSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Speaker recognition") {
                Picker("Diarization", selection: diarizationModeBinding) {
                    ForEach(diarizationModes, id: \.0) { mode, label in
                        Text(label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("Auto detects whether to label speakers based on the audio. Off disables labeling entirely.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Engine", selection: diarizationEngineBinding) {
                    ForEach(DiarizationEngine.allCases, id: \.self) { engine in
                        Text(engine.label).tag(engine)
                    }
                }

                Picker("Expected speakers", selection: expectedSpeakersBinding) {
                    ForEach(DiarizationSpeakerCountHint.allCases, id: \.self) { hint in
                        Text(hint.label).tag(hint)
                    }
                }
            }

            Section("Model registry") {
                modelRegistryRows
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Speech & Models")
    }

    // MARK: - Bindings (use the same AppViewModel methods the old view used)

    private var diarizationModes: [(DiarizationModeUIChoice, String)] {
        [
            (.auto, "Auto"),
            (.on, "On"),
            (.off, "Off"),
        ]
    }

    private var diarizationModeBinding: Binding<DiarizationModeUIChoice> {
        Binding(
            get: { /* derive from viewModel.appSettings — match logic in SessionShelfModelSettingsView */
                if !viewModel.appSettings.isSpeakerDiarizationEnabled { return .off }
                return /* auto vs on based on existing logic */ .auto
            },
            set: { newValue in
                /* call the same setter the old view used */
            }
        )
    }

    private var diarizationEngineBinding: Binding<DiarizationEngine> {
        Binding(
            get: { viewModel.appSettings.diarizationEngine },
            set: { viewModel.appSettings.diarizationEngine = $0 }
        )
    }

    private var expectedSpeakersBinding: Binding<DiarizationSpeakerCountHint> {
        Binding(
            get: { viewModel.appSettings.diarizationExpectedSpeakerCountHint },
            set: { viewModel.appSettings.diarizationExpectedSpeakerCountHint = $0 }
        )
    }

    @ViewBuilder
    private var modelRegistryRows: some View {
        // Migrate the model registry rendering from SessionShelfModelSettingsView
        // Each row: model name, status (Ready / Downloading / Error), "Open in Finder" button
        // Keep the same bindings — do not invent new state.
        EmptyView()  // placeholder — replace with the actual rendering from the old view
    }
}

// Helper enum used only for the segmented control mapping
enum DiarizationModeUIChoice: Hashable {
    case auto, on, off
}
```

**Important:** the `diarizationModeBinding` getter and setter must replicate exactly how `SessionShelfModelSettingsView` translates between the three-way UI (Auto / On / Off) and `AppSettings.isSpeakerDiarizationEnabled` (which is just a Bool). If the existing view uses a different state for the "Auto" distinction (e.g., a separate `diarizationAutoMode: Bool` field on AppSettings, or a derived heuristic), preserve that behavior verbatim.

If `DiarizationEngine` or `DiarizationSpeakerCountHint` don't conform to `CaseIterable`, either add the conformance (one-line change) or replace `ForEach(.allCases)` with an explicit list of the cases used by the old view.

`modelRegistryRows`: copy the rendering verbatim from `SessionShelfModelSettingsView` into this `@ViewBuilder`. If it has its own subviews/styles, leave them intact — only the outer container changes (from custom panel to Form section).

- [ ] **Step 3: Update `SettingsView.swift`**

Remove the inline `private struct SpeechModelsSettingsTab` stub from `SettingsView.swift`.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: clean build. If `DiarizationModeUIChoice` causes conflict with an existing type, rename it.

- [ ] **Step 5: Manual smoke test**

Open Settings → Speech & Models tab. Confirm:
- Diarization segmented control shows Auto / On / Off with the current value selected
- Engine picker shows the current engine
- Expected speakers picker shows the current hint
- Model registry list renders with each model's status

Toggle each and verify persistence + that the existing Recorder behavior still uses these values (e.g., recording with diarization off does not enroll speakers).

- [ ] **Step 6: Commit**

```bash
git add Sources/Lorre/Features/Settings/SpeechModelsSettingsTab.swift Sources/Lorre/Features/Settings/SettingsView.swift
git commit -m "Add SpeechModelsSettingsTab (diarization + model registry)"
```

---

## Task 4: SpeakersSettingsTab

**Files:**
- Create: `Sources/Lorre/Features/Settings/SpeakersSettingsTab.swift`
- Modify: `Sources/Lorre/Features/Settings/SettingsView.swift` (remove the inline `SpeakersSettingsTab` stub)

- [ ] **Step 1: Read existing speaker recognition UI**

Open `Sources/Lorre/Features/Shell/SpeakerRecognitionQuickAccessView.swift`. Identify the list of known speakers, the actions (Re-enroll, Remove, Enroll new), and the `viewModel` bindings used.

- [ ] **Step 2: Create `SpeakersSettingsTab.swift`**

```swift
import SwiftUI

struct SpeakersSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Known speakers") {
                if viewModel.knownSpeakers.isEmpty {
                    Text("No speakers enrolled yet. Lorre will offer to enroll voices it recognizes after a transcript completes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.knownSpeakers) { speaker in
                        speakerRow(for: speaker)
                    }
                }
            }

            Section {
                HStack {
                    Button("Enroll new speaker…") {
                        // call the same enrollment trigger the existing view uses
                    }
                    .buttonStyle(.borderedProminent)

                    if !viewModel.knownSpeakers.isEmpty {
                        Button("Remove all…", role: .destructive) {
                            // call the same removal trigger the existing view uses
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Speakers")
    }

    @ViewBuilder
    private func speakerRow(for speaker: KnownSpeaker) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.displayName).font(.body)
                Text(speakerSubtitle(for: speaker))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Re-enroll") {
                // same trigger as old view
            }
        }
    }

    private func speakerSubtitle(for speaker: KnownSpeaker) -> String {
        // Match the subtitle formatting used in SpeakerRecognitionQuickAccessView
        // (e.g., "Enrolled from <session title> · <duration>")
        return ""  // replace with the exact formatting from the old view
    }
}
```

**Migration notes:**
- `viewModel.knownSpeakers` — use whatever the existing view named the list. Could be `viewModel.speakerLibrary.speakers` or similar; check `SpeakerRecognitionQuickAccessView` for the actual property path.
- `KnownSpeaker` — use the actual type the existing view consumes.
- Button actions — reuse the exact methods the old view invoked. Don't reinvent enrollment logic.

If the speaker list comes from a separate store (e.g., `KnownSpeakerStore`), make sure the tab observes it the same way the old view did.

- [ ] **Step 3: Update `SettingsView.swift`**

Remove the inline `private struct SpeakersSettingsTab` stub.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: clean build.

- [ ] **Step 5: Manual smoke test**

Open Settings → Speakers. Confirm enrolled speakers render (or "No speakers enrolled yet…" if empty). Re-enroll and Remove buttons trigger the same flows as the old quick-access view.

- [ ] **Step 6: Commit**

```bash
git add Sources/Lorre/Features/Settings/SpeakersSettingsTab.swift Sources/Lorre/Features/Settings/SettingsView.swift
git commit -m "Add SpeakersSettingsTab (known speakers library)"
```

---

## Task 5: AboutSettingsTab

**Files:**
- Create: `Sources/Lorre/Features/Settings/AboutSettingsTab.swift`
- Modify: `Sources/Lorre/Features/Settings/SettingsView.swift` (remove the inline `AboutSettingsTab` stub)

- [ ] **Step 1: Create `AboutSettingsTab.swift`**

```swift
import SwiftUI

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 12)
            LorreWordmark()
                .font(.system(size: 48))  // override the DS wordmark size for the About hero
            VStack(spacing: 2) {
                Text("Lorre")
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(versionLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                Text("Powered by ").foregroundStyle(.secondary) +
                Text("FluidAudio").foregroundStyle(.primary)
                Link("github.com/thijsleufkens/Lorre", destination: URL(string: "https://github.com/thijsleufkens/Lorre")!)
                    .font(.callout)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("About")
    }

    private var versionLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}
```

**Note on the `LorreWordmark` font override:** the DS `wordmark` token is 22pt; for the About hero we want it larger. Apply `.font(.custom("Iowan Old Style", size: 48).italic())` directly if the default DS size is too small. Adjust freely — this is the one place where wordmark hierarchy matters.

Actually, cleaner: extend `LorreWordmark` to accept an optional size parameter, OR just create the larger version inline:

```swift
Text("Lorre")
    .font(.custom("Iowan Old Style", size: 48).italic())
    .foregroundStyle(DS.ColorToken.serifInk)
```

Use the inline form to avoid bloating the `LorreWordmark` view's API.

- [ ] **Step 2: Update `SettingsView.swift`**

Remove the inline `private struct AboutSettingsTab` stub.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: clean build.

- [ ] **Step 4: Manual smoke test**

Open Settings → About. Confirm: large italic-serif "Lorre" hero, version info, FluidAudio credit, GitHub link (clickable, opens browser).

- [ ] **Step 5: Commit**

```bash
git add Sources/Lorre/Features/Settings/AboutSettingsTab.swift Sources/Lorre/Features/Settings/SettingsView.swift
git commit -m "Add AboutSettingsTab (wordmark hero + version + credits)"
```

---

## Task 6: SourceModeSegmentedControl

**Files:**
- Create: `Sources/Lorre/Features/Shell/SourceModeSegmentedControl.swift`

- [ ] **Step 1: Create the component**

```swift
import SwiftUI

struct SourceModeSegmentedControl: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Picker("Source", selection: sourceBinding) {
            Text("Mic").tag(RecordingSource.microphone)
            Text("Mic + System").tag(RecordingSource.microphoneAndSystemAudio)
            Text("System").tag(RecordingSource.systemAudio)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 280)
        .disabled(!isPickerEnabled)
    }

    private var sourceBinding: Binding<RecordingSource> {
        Binding(
            get: { viewModel.appSettings.selectedRecordingSource },
            set: { viewModel.appSettings.selectedRecordingSource = $0 }
        )
    }

    private var isPickerEnabled: Bool {
        // Enabled only when on the Recorder route AND not actively recording/processing.
        // Match the existing recordingState check used elsewhere in the app.
        guard case .recorder = viewModel.workStageRoute else { return false }
        return !viewModel.isRecording && !viewModel.isStoppingRecording
    }
}
```

**Property names to verify:** `viewModel.workStageRoute`, `viewModel.isRecording`, `viewModel.isStoppingRecording`. Open `Sources/Lorre/Features/Shell/AppViewModel.swift` and confirm the actual property names. The current Recorder pane uses these or near-equivalents — match exactly.

If the existing app uses a single state enum like `viewModel.recordingState` that bundles idle/recording/finalizing, swap the two booleans for a single `viewModel.recordingState == .idle` check.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lorre/Features/Shell/SourceModeSegmentedControl.swift
git commit -m "Add SourceModeSegmentedControl for window toolbar"
```

---

## Task 7: Add toolbar to AppShellView (source + gear)

**Files:**
- Modify: `Sources/Lorre/Features/Shell/AppShellView.swift`

- [ ] **Step 1: Read the current AppShellView**

Open `Sources/Lorre/Features/Shell/AppShellView.swift`. Note the root structure: a `GeometryReader` containing the sidebar + main work-stage. The `.toolbar { }` modifier needs to attach to a view that is inside the WindowGroup hierarchy — `AppShellView`'s body is the right level.

- [ ] **Step 2: Add `.toolbar` modifier**

In the `body` of `AppShellView`, attach a toolbar to the outermost `GeometryReader` (or whatever the root view of `body` is). Add an `@Environment(\.openSettings)` declaration at the top of the struct (macOS 14+ API, matches our minimum target):

```swift
struct AppShellView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.openSettings) private var openSettings  // <- add this

    var body: some View {
        GeometryReader { geometry in
            // ... existing content
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                SourceModeSegmentedControl(viewModel: viewModel)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Open Settings")
            }
        }
    }
}
```

`\.openSettings` is the canonical SwiftUI macOS 14+ way to open the Settings scene from anywhere in the view hierarchy. The SwiftUI `Settings { }` scene already wires CMD+, system-wide, so we deliberately do **not** also add `.keyboardShortcut(",", modifiers: .command)` on the toolbar button — that would create a duplicate binding and SwiftUI would log a runtime warning.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: clean build.

- [ ] **Step 4: Manual smoke test**

Build + launch. The window now has a toolbar at the top with:
- Segmented Mic / Mic + System / System in the center
- Gear icon on the right

Click the gear → Settings opens. Press CMD+, → Settings opens. Click a segmented option → recording source persists.

When you start a recording (or navigate to processing/transcript route), the segmented control should grey out (`.disabled`).

- [ ] **Step 5: Commit**

```bash
git add Sources/Lorre/Features/Shell/AppShellView.swift
git commit -m "Add window toolbar: source segmented + Settings gear"
```

---

## Task 8: Strip Recorder pane to minimal hero

**Files:**
- Modify: `Sources/Lorre/Features/Recorder/RecorderStageViews.swift`

- [ ] **Step 1: Read the full file**

Read `Sources/Lorre/Features/Recorder/RecorderStageViews.swift` (~1100 lines). Identify the pre-recording setup view (`RecorderConsoleView` or similar) and the active-recording view. **Only the pre-recording setup is stripped here**; the active-recording panel and processing/preview views stay intact.

- [ ] **Step 2: Replace the pre-recording layout**

The current pre-recording layout contains: title block, three source-mode cards, retention section, processing profile section, speaker library quick-access, start button, models status panel. Replace this entire block with:

```swift
private struct RecorderSetupView: View {  // rename or reuse the existing struct name
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            VStack(alignment: .leading, spacing: 4) {
                Text("— Recorder")
                    .font(DS.FontStyle.sectionLabel)
                    .foregroundStyle(DS.ColorToken.serifInk)
                Text(viewModel.recorderHeroTitle)
                    .font(DS.FontStyle.panelTitle)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
            }

            Button {
                viewModel.startRecording()  // use whatever method the old Start button called
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(DS.ColorToken.accentLive)
                        .frame(width: 10, height: 10)
                    Text("Start recording")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.ColorToken.accentPrimary)
            .controlSize(.large)
            .disabled(!viewModel.canStartRecording)  // use the existing computed property if available

            VStack(alignment: .leading, spacing: 4) {
                Text(sourceLine)
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                HStack(spacing: 4) {
                    Text(preferencesLine)
                        .font(DS.FontStyle.helper)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.ColorToken.fgSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open Settings")
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Space.x6)
    }

    private var sourceLine: String {
        switch viewModel.appSettings.selectedRecordingSource {
        case .microphone: return "Microphone · 48 kHz"
        case .microphoneAndSystemAudio: return "Microphone + system audio · 48 kHz"
        case .systemAudio: return "System audio · 48 kHz"
        }
    }

    private var preferencesLine: String {
        let live = viewModel.appSettings.isLiveTranscriptionEnabled ? "Live preview on" : "Live preview off"
        let retention = viewModel.appSettings.isDeleteAudioAfterTranscriptionEnabled ? "Delete after transcript" : "Keep audio"
        return "\(live) · \(retention)"
    }
}
```

**Important — property name verification:**
- `viewModel.recorderHeroTitle` — likely doesn't exist by that name. Look in the current `RecorderConsoleView` for the existing title binding (could be `viewModel.activeStageTitle`, `viewModel.draftSessionTitle`, or similar). Use whatever already drives the title. If no obvious binding exists, fall back to a hardcoded "New recording" until a session is created.
- `viewModel.startRecording()` — match the existing call site for the Start button in the old view.
- `viewModel.canStartRecording` — match the existing disabled-state computation. If there's no single property, replicate the same conjunction the old Start button used (e.g., models ready AND not already recording).

**Important — what to remove from the file:**
- The three source-mode card button styles (`RecorderSourceOptionButtonStyle`) — delete the struct entirely if it's only used by the now-removed source-cards.
- The retention section view — delete.
- The processing profile section — delete.
- The speaker library quick-access embed — delete.
- The "Models / Models ready" status panel — delete.
- The `RecorderStartActionButtonStyle` — delete if it's only used by the now-removed custom Start button. The new Start uses native `.buttonStyle(.borderedProminent)` instead.

**Keep:** the active-recording view (timer + waveform + buttons), processing pipeline view, live-transcript preview card. Only the **pre-recording setup** is stripped.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: clean build. If unused helper structs are flagged as unreferenced (which is the goal), delete them.

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: 54/54 pass. No test should be broken by this change since none of the deleted views are exercised by unit tests.

- [ ] **Step 5: Manual smoke test**

Launch the app. The Recorder pane now shows only:
- "— Recorder" kicker
- Hero title
- Native blue/moss Start recording button
- Two status lines (source · sample rate; preferences · gear icon)

Click Start → recording begins as before. Click the gear in the status line → Settings opens.

- [ ] **Step 6: Commit**

```bash
git add Sources/Lorre/Features/Recorder/RecorderStageViews.swift
git commit -m "Strip Recorder pre-recording pane to minimal hero"
```

---

## Task 9: Clean up sidebar (remove wordmark + obsolete panels)

**Files:**
- Modify: `Sources/Lorre/Features/Shell/SessionShelfSidebarView.swift`

- [ ] **Step 1: Read SessionShelfSidebarView**

Note the locations of (a) the `LorreWordmark` block at the top, (b) any embed of `SessionShelfModelSettingsView`, (c) any embed of `SpeakerRecognitionQuickAccessView`.

- [ ] **Step 2: Remove the wordmark block**

Delete the `LorreWordmark()` block at the top of the sidebar (added in the prior Sage refresh). The block looks like:

```swift
LorreWordmark()
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, DS.Space.x4)
    .padding(.bottom, DS.Space.x2)
```

Delete it. The first child of the sidebar should now be the search field (or whatever was directly below the wordmark).

- [ ] **Step 3: Remove model settings + speaker quick-access embeds**

If `SessionShelfModelSettingsView` and/or `SpeakerRecognitionQuickAccessView` are embedded inside the sidebar (likely at the bottom), delete those embeds. Their content now lives in Settings tabs.

The files themselves stay on disk (their internals were copy-source for the Settings tabs); just stop referencing them from the sidebar. They become unused — the build will warn but not fail. We delete the files in Task 10.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: clean build, maybe with warnings about unused types in `SessionShelfModelSettingsView` or `SpeakerRecognitionQuickAccessView`.

- [ ] **Step 5: Manual smoke test**

Launch. Sidebar shows: search field → date-grouped sessions list → footer actions. No more "Lorre" wordmark at the top. No more model status or speaker recognition panel at the bottom.

The window title bar still shows "Lorre" (system chrome).

- [ ] **Step 6: Commit**

```bash
git add Sources/Lorre/Features/Shell/SessionShelfSidebarView.swift
git commit -m "Remove wordmark and obsolete model/speaker panels from sidebar"
```

---

## Task 10: Delete obsolete sidebar files

**Files:**
- Delete: `Sources/Lorre/Features/Shell/SessionShelfModelSettingsView.swift`
- Delete: `Sources/Lorre/Features/Shell/SpeakerRecognitionQuickAccessView.swift`

- [ ] **Step 1: Verify no remaining references**

```bash
grep -rn "SessionShelfModelSettingsView\|SpeakerRecognitionQuickAccessView" Sources/
```

Expected: zero references after Task 9. If anything still references either type, address those references first (extract whatever logic they need into the Settings tabs or remove the call sites).

- [ ] **Step 2: Delete the files**

```bash
rm Sources/Lorre/Features/Shell/SessionShelfModelSettingsView.swift
rm Sources/Lorre/Features/Shell/SpeakerRecognitionQuickAccessView.swift
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: clean build.

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: 54/54 pass.

- [ ] **Step 5: Commit**

```bash
git add -A Sources/Lorre/Features/Shell/SessionShelfModelSettingsView.swift Sources/Lorre/Features/Shell/SpeakerRecognitionQuickAccessView.swift
git commit -m "Remove obsolete model settings and speaker quick-access views"
```

---

## Task 11: Full verification

**Files:** (none — verification only)

- [ ] **Step 1: Run the full test suite**

```bash
swift test
```
Expected: 54/54 pass.

- [ ] **Step 2: Build release .app**

```bash
./scripts/package_macos_app.sh release
```
Expected: `dist/Lorre.app` produced.

- [ ] **Step 3: Install and launch**

```bash
rm -rf /Applications/Lorre.app
cp -R dist/Lorre.app /Applications/
open /Applications/Lorre.app
```

- [ ] **Step 4: Acceptance check (light mode)**

System Settings → Appearance → Light. Verify:
- Window toolbar shows: segmented Mic / Mic + System / System + gear icon
- Sidebar: no "Lorre" wordmark; search field at top; date-grouped sessions; no model status panel; no speaker recognition panel
- Recorder pane: italic-serif "— Recorder" kicker, hero title, native moss/borderedProminent Start button, two status lines with a small gear at the end
- CMD+, opens Settings window with 4 tabs (General / Speech & Models / Speakers / About)
- All 4 tabs render their content as designed; toggles persist
- The window-toolbar gear opens the same Settings window
- The status-line gear opens the same Settings window

- [ ] **Step 5: Acceptance check (dark mode)**

System Settings → Appearance → Dark. Verify the same as Step 4, with the dark palette. Sage tokens already dynamic from prior PR.

- [ ] **Step 6: Behavior preservation check**

Run a real recording end-to-end:
- Pick a source via the toolbar segmented control
- Hit Start
- Speak for ~10 seconds
- Stop
- Verify the session lands in the sidebar
- Open it → transcript renders normally

Then change a preference in Settings (e.g., toggle Live preview), close Settings, start another recording, and confirm the new pref takes effect.

- [ ] **Step 7: Edge case — narrow window**

Resize the window to its minimum (1120×760). Verify:
- Toolbar still readable
- Recorder pane doesn't overflow
- Sidebar still functional

- [ ] **Step 8: Edge case — CMD+, when Settings already open**

With Settings already open, press CMD+, again. Expected: the existing Settings window comes forward (Apple-native behavior). No second window.

- [ ] **Step 9: Edge case — Source-selector during recording**

Start a recording. Verify the toolbar source-selector becomes `.disabled` (greyed out, not interactable). Stop the recording → the selector re-enables.

If any of these checks fail, fix with small follow-up commits before marking the task complete.

---

## Out of plan

Per the spec, these are explicitly NOT in this sub-project:
- Vibrancy / `.regularMaterial` / `NSVisualEffectView` (Sub-project B)
- `.listStyle(.sidebar)` or native source-list selection styling (Sub-project B)
- Custom italic-serif title in macOS window title bar (Sub-project B if pursued)
- Visual polish on Processing pipeline view, Transcript view, banners (Sub-project C)
- Language hint in Settings (deferred — `AppSettings.languageHint` doesn't exist; YAGNI)
- New app features

If anything beyond this scope comes up during implementation, file as a follow-up and don't expand the plan inline.
