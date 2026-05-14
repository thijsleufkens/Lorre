# Recorder + Settings — Apple-native restructure

**Status:** brainstormed, awaiting implementation plan
**Date:** 2026-05-14
**Branch:** `claude/apple-native-recorder`
**Sub-project:** A of three (this one) — B = sidebar native chrome, C = remaining pane polish

## Doel

De huidige Recorder-hoofdpane toont vóór elke opname een wand aan toggles: capture mode (3 kaarten), retention (Keep / Delete), processing profile, speaker recognition, live preview, speaker library. Dat voelt "Windows/Linux/web-app" — geen Apple-app. Apple-apps tonen op de hoofdpane vooral de **primaire actie**; voorkeuren wonen in een Settings window (CMD+,).

Deze restructure verhuist voorkeuren naar een echte SwiftUI `Settings` scene met 4 tabs, en reduceert de Recorder-hoofdpane tot: kicker, hero-titel, één grote Start-knop, één statusregel. Bron-keuze (Mic / Mic+System / System) verhuist naar de **window-toolbar** als segmented control. Het settings-tandwiel zit naast de source-selector.

Sage-palette en italic serif voice blijven. De `LorreWordmark` als kop van de sidebar verdwijnt — het window-title-bar zegt al "Lorre"; de wordmark overleeft in de About-tab.

## Scope

**In scope**
- Nieuwe SwiftUI `Settings` scene met 4 tabs (General / Speech & Models / Speakers / About).
- Recorder-hoofdpane gestript tot: kicker, titel, Start-knop, statusregel.
- Window-toolbar met source segmented control + tandwiel-knop.
- `LorreWordmark` verwijderd uit `SessionShelfSidebarView`.
- Verhuizing van bestaande voorkeur-UI: retention, live preview, language hint, diarization mode/engine/expected-speakers, model registry, speaker library.
- Statusregel onder Start-knop reflecteert actieve prefs en linkt naar Settings.
- `AppSettings` (schemaVersion 2) blijft ongewijzigd — alleen de UI verandert, niet de data.
- Acceptance: alle bestaande functionaliteit is bereikbaar, alle 54 tests blijven groen.

**Out of scope**
- Vibrancy / `NSVisualEffectView` / `.regularMaterial` (Sub-project B).
- `.listStyle(.sidebar)` of native source-list selectiekleur (Sub-project B).
- Custom italic-serif titel in macOS title bar (vereist NSTitlebarAccessoryViewController — Sub-project B als wenselijk).
- Visuele opfris van Processing pipeline, Transcript view, banners (Sub-project C).
- Nieuwe app-features of gedragsveranderingen.

## Designtokens

Geen nieuwe tokens. Alleen relocatie van bestaande UI met de Sage-tokens uit de vorige refresh.

## Componenten

### Settings scene

**Nieuwe SwiftUI scene** in `LorreApp.swift`:

```swift
Settings {
    SettingsView(viewModel: viewModel)
}
```

SwiftUI's `Settings` scene wired CMD+, en Lorre menu > Settings automatisch.

### `SettingsView` (root container)

`Sources/Lorre/Features/Settings/SettingsView.swift` — root container met `TabView` en `.tabItem` per tab. Width vastgepind op 540pt (Apple standaard).

```swift
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
```

Elk tab uses `Form { Section { ... } }` voor native Apple Form-layout.

### `GeneralSettingsTab.swift`

Drie secties:
- **Audio** — "Source audio after transcript": segmented `Picker` (`Keep audio` / `Delete after transcript`). Bound to `AppSettings.isDeleteAudioAfterTranscriptionEnabled`.
- **Live transcription** — `Toggle("Show live preview while recording")`. Bound to `AppSettings.isLiveTranscriptionEnabled`. Helper text uitleg.
- **Language** — `Picker("Language hint for transcription")` met "Auto-detect" en 25 European languages. Bound to existing language hint setting (er bestaat al een language hint binding in `AppSettings` — controleren en hergebruiken).

### `SpeechModelsSettingsTab.swift`

Twee secties:
- **Speaker recognition**
  - "Diarization mode" segmented: Auto / On / Off. Bound to `AppSettings.isSpeakerDiarizationEnabled` + impliciete mode.
  - "Diarization engine" `Picker`. Bound to `AppSettings.diarizationEngine`.
  - "Expected speakers" `Picker`. Bound to `AppSettings.diarizationExpectedSpeakerCountHint`.
- **Model registry**
  - Per-model rij: naam, status (Ready / Downloading / Error), "Open in Finder" knop. Hergebruikt de logic die nu in `SessionShelfModelSettingsView` zit.

### `SpeakersSettingsTab.swift`

Eén sectie **Known speakers** — list van enrolled speakers met:
- Naam + helper "Enrolled from ‹session›"
- Per rij `Re-enroll` knop
- Onderaan: `+ Enroll new speaker…` (primary) + `Remove all…` (destructive secondary)

Hergebruikt logica uit `SpeakerRecognitionQuickAccessView` (de "Manage…" knop daarheen verdwijnt — de speakers tab IS nu de speaker library).

### `AboutSettingsTab.swift`

Eenvoudige statische tab:
- `LorreWordmark` view (italic-serif "Lorre") + versienummer eronder
- "Powered by FluidAudio" + link naar `https://fluidinference.com`
- GitHub repo link
- Open Source Acknowledgements knop (optioneel — kan in v1 een placeholder zijn)

### Recorder-hoofdpane (`RecorderConsoleView` in `RecorderStageViews.swift`)

Wordt drastisch gestript:

```
┌─────────────────────────────────────┐
│ — Recorder                          │ ← kicker (italic serif)
│ Klantgesprek Aurora                 │ ← hero title (sf-pro 26pt)
│                                     │
│  ⏺  Start recording                 │ ← bordered prominent, large, moss
│                                     │
│ Microphone + system audio · 48 kHz  │ ← status line (helper, fgSecondary)
│ Live preview off · Keep audio · ⚙   │ ← second status line + gear link
└─────────────────────────────────────┘
```

Wat verdwijnt: `RecorderSourceOptionButtonStyle` (de drie kaarten), de retention sectie, de processing profile sectie, de speaker library quick-access. Code blijft in `RecorderStageViews.swift` bestaan voor de tijdens-opname / processing / preview-stages, maar de pre-recording setup wordt deze minimal hero-layout.

### Window toolbar

In `AppShellView.swift` (of `LorreApp.swift`'s WindowGroup), via `.toolbar { }`:

```swift
.toolbar {
    ToolbarItem(placement: .principal) {
        SourceModeSegmentedControl(viewModel: viewModel)
    }
    ToolbarItem(placement: .primaryAction) {
        Button {
            // Open Settings — handled via NSApplication.shared
        } label: {
            Image(systemName: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
```

`SourceModeSegmentedControl` is een nieuwe view in `Sources/Lorre/Features/Shell/SourceModeSegmentedControl.swift` met `Picker(selection:) { ... }.pickerStyle(.segmented)`. Drie cases: `.microphone` (label "Mic"), `.microphoneAndSystemAudio` (label "Mic + System"), `.systemAudio` (label "System").

**Belangrijk**: de source-selector is alleen actief op `WorkStageRoute == .recorder` met `recordingState == .idle`. Zodra opname loopt, of route processing/transcript is, wordt de segmented control `.disabled(true)` (niet hidden — voorkomt sprongen in toolbar-layout). Het gear-icoon blijft altijd actief.

### Sidebar

`SessionShelfSidebarView.swift`: `LorreWordmark` block verdwijnt uit de top van de sidebar. De datum-grouping en sessie-rijen blijven 100% gelijk. De rest van de sidebar verandert niet in deze sub-project.

### Models status

De huidige "Models / Models ready" panel onder in de sidebar verdwijnt uit de Recorder-pane (verhuist conceptueel naar Settings > Speech & Models). Optioneel: een onopvallende inline-banner in de Recorder-pane verschijnt **alleen als models NIET ready** zijn (downloading / error). In Sage-stijl: een dunne strip aan de top met clay/error-tint en een link naar Settings.

## Bindings en state

Geen wijziging aan view models of `AppSettings`. Bindings die nu in Recorder-pane zitten verschuiven naar de Settings tabs:

| Setting | From | To |
|---|---|---|
| `isDeleteAudioAfterTranscriptionEnabled` | Recorder pane "Retention" sectie | Settings > General |
| `isLiveTranscriptionEnabled` | Recorder pane "Processing profile" | Settings > General |
| `isSpeakerDiarizationEnabled` | Recorder pane | Settings > Speech & Models |
| `diarizationEngine` | Recorder pane | Settings > Speech & Models |
| `diarizationExpectedSpeakerCountHint` | Recorder pane | Settings > Speech & Models |
| `selectedRecordingSource` | Recorder pane source-cards | Window toolbar segmented control |
| Known speakers | `SpeakerRecognitionQuickAccessView` | Settings > Speakers |

`AppViewModel` blijft de single source of truth. De Settings tabs binden direct op dezelfde `viewModel.appSettings.xxx` properties. Wijzigingen persisteren direct (Apple-conventie — geen Save-knop), via de bestaande `AppSettingsStore`.

## Statusregel (Recorder pane)

Twee regels onder de Start-knop, beide `DS.FontStyle.helper` in `fgSecondary`:

1. Regel 1 — beschrijft de actieve session-setup: `"<source name> · 48 kHz"` (bv. "Microphone + system audio · 48 kHz").
2. Regel 2 — actieve preferences: `"Live preview <on/off> · <Keep audio / Delete after transcript>"` met een klein gear-icoontje aan het einde dat naar Settings springt. Tap op een waarde springt naar het juiste tab. Met de keyboard kan CMD+, dezelfde Settings openen.

Doel: gebruiker weet zonder Settings open te klikken wat er gaat gebeuren bij Start.

## Bestanden

**Nieuw:**
- `Sources/Lorre/Features/Settings/SettingsView.swift`
- `Sources/Lorre/Features/Settings/GeneralSettingsTab.swift`
- `Sources/Lorre/Features/Settings/SpeechModelsSettingsTab.swift`
- `Sources/Lorre/Features/Settings/SpeakersSettingsTab.swift`
- `Sources/Lorre/Features/Settings/AboutSettingsTab.swift`
- `Sources/Lorre/Features/Shell/SourceModeSegmentedControl.swift`

**Gewijzigd:**
- `Sources/Lorre/App/LorreApp.swift` — add `Settings { ... }` scene
- `Sources/Lorre/Features/Shell/AppShellView.swift` — add `.toolbar { ... }` modifier
- `Sources/Lorre/Features/Shell/SessionShelfSidebarView.swift` — verwijder `LorreWordmark`
- `Sources/Lorre/Features/Recorder/RecorderStageViews.swift` — strip `RecorderConsoleView` pre-recording layout naar minimal
- `Sources/Lorre/Features/Shell/SessionShelfModelSettingsView.swift` — verwijderd zodra alles in SpeechModelsSettingsTab zit, of behouden als deprecated tot Sub-project B
- `Sources/Lorre/Features/Shell/SpeakerRecognitionQuickAccessView.swift` — verwijderd of vereenvoudigd

## Migratie

Geen data-migratie. `AppSettings` schemaVersion blijft 2. Existing user preferences zoals retention, live preview, diarization mode/engine blijven exact dezelfde waarden — alleen hun UI-locatie verandert.

Window state: standaard SwiftUI Settings scene gedraagt zich Apple-native (CMD+, opent het, tweede CMD+, focused het bestaande venster).

## Acceptance criteria

- [ ] CMD+, opent een Settings window met 4 tabs (General / Speech & Models / Speakers / About).
- [ ] Recorder hoofdpane toont **alleen**: italic-serif kicker "— Recorder", hero session-titel, Start-knop, twee-regel statusregel met gear-link. Geen source-cards, geen retention-sectie, geen processing-profile sectie, geen speaker-library sectie.
- [ ] Window-toolbar toont segmented source-selector + gear-knop. Source-selector is alleen aanklikbaar in pre-recording idle state; tijdens recording / processing / transcript is hij `.disabled` (zichtbaar maar grijs).
- [ ] Sidebar toont géén `LorreWordmark` meer aan de top.
- [ ] Alle bestaande prefs zijn bereikbaar via Settings en werken identiek (retention, live preview, language, diarization, expected speakers, speaker library).
- [ ] Alle bestaande sessions / transcripts blijven openen zonder issue (geen data-migratie).
- [ ] 54+ tests blijven groen.
- [ ] Light + dark mode beide goed.
- [ ] Smalle window (1120×760) breekt niet.
- [ ] Tweede CMD+, focused bestaande Settings window (Apple default gedrag).

## Risico's

1. **Window-toolbar in SwiftUI op macOS heeft beperkingen.** `ToolbarItem(placement: .principal)` kan een segmented control bevatten maar de styling matched niet altijd 1:1 met native NSToolbar. Bij visuele afwijkingen accepteren we het SwiftUI-default (geen NSToolbarController custom).
2. **`Settings { ... }` scene op macOS 14+.** Toggle-syncing met main `AppViewModel`: omdat het Settings window in een aparte scene leeft, moet `viewModel` als `@StateObject` op App-niveau worden gedeeld (niet opnieuw geconstrueerd). Bestaande pattern: `@StateObject private var viewModel = AppViewModel(...)` in `LorreApp`. We injecteren dezelfde instance in beide scenes.
3. **Statusregel "klik op waarde springt naar tab".** SwiftUI heeft geen programmatische API om een specifieke Settings-tab te openen via Apple's standaard Settings scene. Compromise: gear-klik opent gewoon de Settings window (last-used tab — Apple-default). Geen deep-link naar specifieke tab in v1.
4. **De `LorreWordmark` wordt nog gebruikt in About-tab.** Dus het bestand blijft. Geen dead code.
5. **Source-mode toolbar tijdens recording.** Tijdens een actieve opname mag je de source niet meer wijzigen. We disablen de segmented control (`.disabled(true)`) tijdens recording / processing — niet hiden, om sprongen in toolbar-layout te voorkomen.
6. **Talen-picker.** Als er momenteel geen language-hint binding bestaat in `AppSettings`, voegen we er één toe (schemaVersion blijft 2 want het is een optioneel veld dat default `nil` is en niet bestaande data invalideert — zie `SessionManifest.schemaVersion` fallback patroon voor precedent).

## Open vragen

Geen.

---

## Implementatievolgorde voorstel (voor de plan-fase)

1. Add `Settings` scene skeleton + empty 4 tabs (CMD+, works, but tabs zijn placeholder).
2. Bouw `GeneralSettingsTab` (retention + live preview + language).
3. Bouw `SpeechModelsSettingsTab` (diarization + model registry).
4. Bouw `SpeakersSettingsTab` (known speakers list).
5. Bouw `AboutSettingsTab`.
6. Voeg `SourceModeSegmentedControl` + `.toolbar` modifier toe.
7. Strip `RecorderConsoleView` pre-recording layout.
8. Verwijder `LorreWordmark` uit sidebar.
9. Verwijder of deprecate `SessionShelfModelSettingsView` en `SpeakerRecognitionQuickAccessView`.
10. Build + test + manual visual verification.
