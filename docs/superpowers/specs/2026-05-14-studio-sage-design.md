# Studio Sage — visuele identiteit van Lorre

**Status:** brainstormed, awaiting implementation plan
**Date:** 2026-05-14
**Branch:** `claude/studio-sage-design`

## Doel

Lorre staat nu visueel op "spartaans": pure monochroom (wit/grijs/zwart), systeem-sans overal, vlakke bordered panels, mono-caps labels, geen accentkleur, geen dark mode. De app werkt prima, maar mist warmte en karakter.

Deze refresh introduceert **Studio Sage**: een rustige, volwassen identiteit met een crème-papier canvas (light) of bosgroen canvas (dark), mos-groen als primaire kleur, en klei-oranje als accent voor live state. Italic serif (Iowan Old Style) is de "stem" voor section labels en de Lorre-wordmark; system-sans draagt de UI; system-mono is gereserveerd voor de timer. Soft shadows, ronde hoeken, pill buttons.

Het is een visuele refresh van het bestaande design system. **Geen gedrag wijzigt, geen views worden toegevoegd of verwijderd, geen flow verandert.** Het wordmark en de date-grouping in de sidebar zijn de enige twee nieuwe UI-elementen — beide presentational.

## Scope

**In scope**
- Volledige herziening van `DesignSystem.swift` tokens: kleuren (light + dark), typografie, radii, paddings.
- Dark mode-ondersteuning toevoegen via dynamische `NSColor`-resolvers; volgt het systeem (geen handmatige toggle).
- Pill-style button styles, soft-shadow panel surface modifier.
- Wordmark "Lorre" in sidebar (italic serif).
- Date-grouping in session list ("Today / Yesterday / This week / Earlier") — pure visueel, geen filtering, geen state.
- Toepassen van nieuwe tokens op alle bestaande views: `AppShellView`, `SessionShelfSidebarView`, `RecorderStageViews`, `TranscriptViews`, `TranscriptSegmentRowViews`, `SessionShelfModelSettingsView`, `SpeakerRecognitionQuickAccessView`, en de DS-componenten (`CapsLabel`, `IndexRailView`, `SearchFieldView`, `SpeakerBadgeView`).
- App-level `.preferredColorScheme(nil)` zodat de macOS-systeemvoorkeur respected wordt.

**Out of scope**
- Nieuwe features of flows.
- Layout-veranderingen behalve waar typografische schaalverschillen dat afdwingen (bv. grotere timer vraagt iets meer verticale ruimte in het recorder-paneel).
- Custom fonts bundelen (Inter, JetBrains Mono). We gebruiken systeem-equivalenten: SF Pro en SF Mono via `.system(...)`. Iowan Old Style is system-bundled op macOS 14+.
- App icon herziening.
- Animaties of micro-interacties.
- Accessibility-audit (komt later als eigen werkpakket).

## Designtokens

### Kleuren

Tokens worden dynamisch: ze resolven naar de juiste hex op basis van `NSAppearance` (aqua vs darkAqua). Alle bestaande aanroepen `DS.ColorToken.bgApp` etc. blijven werken.

| Token | Light | Dark | Rol |
|---|---|---|---|
| `bgApp` | `#F1EDE2` (bone) | `#0E1411` (forest) | Window canvas |
| `bgPanel` | `#E5DECB` (deep bone) | `#0A0F0C` (deep forest) | Sidebar background |
| `bgPanelAlt` | `#FFFFFF` (paper) | `#131B17` (forest panel) | Recorder/transcript panel surface |
| `fgPrimary` | `#1F2A24` | `#E5DECB` | Body text |
| `fgSecondary` | `#6F7A6A` | `#7A8576` | Meta text, timestamps |
| `fgTertiary` | `#8A937F` | `#5C6657` | Disabled / placeholder |
| `accentPrimary` | `#4A5D44` (moss) | `#8FA688` (sage light) | Buttons, brandmark, active accent bar |
| `accentLive` | `#CB6F4E` (clay) | `#E08667` (clay light) | Live/recording dot, "Recording" kicker |
| `borderSoft` | `#D8CFB9` | `#1F2A22` | Card borders, dividers |
| `borderStrong` | `#C2C9B5` | `#2A372D` | Pressed button outline, sidebar split |
| `serifInk` | `#4A5D44` | `#8FA688` | Italic serif labels en wordmark |
| `statusReady` | `#4A5D44` | `#8FA688` | (vervangt huidige `#2E7D32`) |
| `statusPreparing` | `#B8893A` | `#C29B3E` | |
| `statusError` | `#B33F2A` | `#E08667` | |
| `statusIdle` | `#8A937F` | `#5C6657` | |

Status-kleuren (`statusReady`/`Preparing`/`Error`/`Idle`) blijven bestaan zodat het bestaande recorder/processing/status-systeem direct werkt; ze worden alleen verschoven naar de nieuwe palette.

Het bestaande `chipBg` / `chipBorder` / `fieldBg` / `fieldBorder` mapping verandert mee:
- `chipBg = bgPanel`, `chipBorder = borderSoft`
- `fieldBg = bgPanelAlt`, `fieldBorder = borderSoft`
- Pure `black` / `white` blijven bestaan als utility tokens (gebruikt door enkele button styles voor on-accent text).

### Typografie

Geen externe fonts. Alles systeem.

| Token | Font | Grootte | Weight | Gebruik |
|---|---|---|---|---|
| `wordmark` | Iowan Old Style, italic | 22 | medium | "Lorre" boven sidebar |
| `appTitle` | SF Pro | 22 | semibold | (legacy — bestaande gebruikspunten houden hetzelfde) |
| `panelTitle` | SF Pro | 26 | semibold (tracking -0.5) | Recorder/transcript hero title |
| `sectionLabel` | Iowan Old Style, italic | 13 | regular | "— Recorder", "— Sessions" |
| `groupHead` | Iowan Old Style, italic | 12 | regular | "Today", "Yesterday" etc. |
| `body` | SF Pro | 13 | regular | Standaard tekst |
| `bodyStrong` | SF Pro | 13 | semibold | Sessietitels in sidebar |
| `control` | SF Pro | 12 | semibold | Button labels |
| `helper` | SF Pro | 11 | regular | Meta-tekst, timestamps |
| `kicker` | SF Pro | 11 | semibold (caps, tracking +1.5) | "RECORDING" boven timer |
| `timer` | SF Mono | 56 | medium (tracking -2) | Hero recorder timer |
| `timerCompact` | SF Mono | 18 | semibold | Inline / sidebar timestamps |
| `mono` | SF Mono | 11 | regular | Technische details |
| `monoStrong` | SF Mono | 12 | semibold | Source-badges |

De huidige `DS.FontStyle.stageStatus` wordt geherinterpreteerd als `kicker` (semantisch hetzelfde — een korte status-label).

### Radii & spacing

| Token | Huidige waarde | Nieuwe waarde | Gebruik |
|---|---|---|---|
| `Radius.sm` | 8 | 8 | Buttons (legacy), small chips |
| `Radius.md` | 12 | 10 | Sidebar item rows |
| `Radius.lg` | 18 | 14 | Recorder/transcript panel |
| `Radius.pill` | — | 999 | Nieuwe pill-button |

Spacing-tokens (`Space.x1` t/m `x8`) blijven exact hetzelfde — geen reden om de bestaande indelingen te verstoren.

### Schaduwen

Twee niveaus, beide gedefinieerd als view modifiers `.dsSurfaceShadow()` en `.dsPanelShadow()`:

- **Surface** (sessie-item, kleine cards): `y: 1, blur: 3, color: bgApp-derived 10%`
- **Panel** (recorder/transcript paneel): `y: 8, blur: 24, color: bgApp-derived 7%` plus een tweede laag `y: 1, blur: 3, color: 4%`

In dark mode worden schaduwen subtieler en zwarter (op een donker canvas zijn schaduwen sowieso onzichtbaarder, maar de extra inset border in `borderSoft` vangt het surface-onderscheid).

## Nieuwe & herziene componenten

### `PillButtonStyle` (primary / secondary)

Vervangt `PrimaryControlButtonStyle` en `SecondaryControlButtonStyle` (behoudt dezelfde Swift-namen voor minimale call-site churn):

- Padding: `horizontal 18, vertical 10`
- Radius: `Radius.pill` (999)
- Primary: `accentPrimary` background, `bgApp` foreground
- Secondary: transparent background, `borderSoft` 1px outline, `fgPrimary` foreground
- Pressed: 8% darker fill (primary) of `bgPanel` fill (secondary)
- Disabled: `fgTertiary` foreground, `bgPanelAlt` background, `borderSoft` outline

De bestaande aanroepen `.buttonStyle(PrimaryControlButtonStyle())` blijven werken — alleen de visuele output is anders.

### `.dsPanelSurface()`

Bestaat al. Wordt herzien:
- Default: `bgPanelAlt` fill, `borderSoft` 1px outline, `Radius.lg` (14)
- `selected:` → `borderStrong` outline + behoud accent-bar indicator (zie volgende component)
- `alt:` → blijft `bgPanel` als legacy hook, gebruikt door bestaande session-item layouts

### `.dsActiveAccentBar()`

Nieuwe modifier: tekent een 2px-brede `accentPrimary`-streep aan de linkerkant van een container, gebruikt voor de active session in de sidebar. Implementatie via `overlay(alignment: .leading)` met een vaste `RoundedRectangle`. Conditional gemaakt zodat hij makkelijk toe te passen is via `.dsActiveAccentBar(isActive: session.isSelected)`.

### `LorreWordmark`

Nieuwe view (`Sources/Lorre/Core/DesignSystem/Components/LorreWordmark.swift`):
- Tekst "Lorre" in `DS.FontStyle.wordmark`
- Kleur: `serifInk`
- Gebruikt in `SessionShelfSidebarView` als header

### `SessionDateGroupHeader`

Nieuwe view: kleine italic serif header die "Today", "Yesterday", "This week", "Earlier" laat zien. Logic om sessies te groeperen leeft in een `SessionDateGroup` helper in `Sources/Lorre/Core/DesignSystem/Components/SessionDateGrouping.swift` (pure functie van `[SessionManifest] -> [(Group, [SessionManifest])]`). Geen ViewModel-changes — de groep wordt afgeleid van `viewModel.sessions` bij render.

## Toepassing per view

### `LorreApp.swift`
Voeg `.preferredColorScheme(nil)` toe en zet `frame(minWidth: 1120, minHeight: 760)` ongewijzigd. Geen verdere wijziging.

### `AppShellView.swift`
- `DS.ColorToken.bgApp.ignoresSafeArea()` blijft, krijgt dynamische kleur.
- Banner-styling (`AppBannerView`) krijgt update naar nieuwe radii en `bgPanelAlt`.
- `ActiveRecordingBadge` en `CapsLabel` worden hieronder beschreven.

### `SessionShelfSidebarView.swift`
- Header krijgt nieuwe `LorreWordmark` bovenaan, gevolgd door een dunne `borderSoft` divider.
- Session lijst krijgt date-grouping via `SessionDateGroupHeader`.
- Session item row: `dsPanelSurface(selected:)` blijft, krijgt extra `.dsActiveAccentBar(isActive: isSelected)` voor de moss-streep links.
- Sessietitel font: `bodyStrong`. Sub-meta (`"14:20 · 32 min"`): `helper` in `fgSecondary`.
- Pill-buttons voor "New session" en eventuele acties in de footer.
- `SearchFieldView` en `IndexRailView` gewoon doorlopen op nieuwe tokens (textfield krijgt `bgPanelAlt` fill).

### `RecorderStageViews.swift`
- Recorder panel: `dsPanelSurface()` met `dsPanelShadow()`.
- Kicker "— Recorder" in `sectionLabel` (italic serif).
- Hero title in `panelTitle`.
- Meta-row ("Microphone · 48 kHz · ready to record"): `helper` in `fgSecondary`.
- "Recording" kicker boven de timer: `kicker` in `accentLive`, met live-dot ervoor (`Circle` 12pt fill `accentLive` met 4pt soft glow via shadow).
- Timer: nieuwe `timer` token (SF Mono 56).
- Waveform balken: `accentPrimary` met opacity 0.75 (light) / 0.88 (dark).
- Pause/Stop: pill-buttons (secondary / primary).
- De active recording badge en stop/pause buttons in `ActiveRecordingWorkspaceView` volgen dezelfde stijl.

### `TranscriptViews.swift` + `TranscriptSegmentRowViews.swift`
- Hero header: `panelTitle` + `sectionLabel` kicker (zelfde patroon als recorder).
- Segment-rijen: `bgPanelAlt` background, `borderSoft` 1px divider tussen segmenten (geen volledige cards, behoudt density).
- Speaker badges (`SpeakerBadgeView`): krijgen `bgPanel` fill met `accentPrimary` text en `borderSoft` outline. Voor "user-renamed" speakers blijft de bestaande `filled`-variant maar dan met `accentPrimary` fill.
- Edit-state (`isEdited`): `borderStrong` left-border + `bgPanelAlt` highlight.
- Export-buttons: pill-buttons.

### `SessionShelfModelSettingsView.swift`
- Sectie-headers met `sectionLabel`.
- Selecties / pickers: native macOS controls, ongewijzigd; alleen surrounding `dsPanelSurface()` met nieuwe tokens.
- Pill-buttons voor "Save" / "Reset to defaults".

### DS-componenten
- `CapsLabel`: caps blijven, krijgen `kicker` font + `accentPrimary` color (was: `fgSecondary`).
- `SearchFieldView`: `fieldBg` (= `bgPanelAlt`) fill, `fieldBorder` outline, `helper` placeholder.
- `IndexRailView`: dunne `borderSoft` verticale rail, dot-indicators in `accentPrimary`, actieve in `accentLive`.
- `SpeakerBadgeView`: zie hierboven.

## Dark mode plumbing

Centraal helper in `DesignSystem.swift`:

```swift
extension Color {
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}
```

Elke `DS.ColorToken.xxx` wordt `Color.dynamic(light: ..., dark: ...)`. Hierdoor reageert het systeem live op `View > Appearance` changes zonder dat we `@Environment(\.colorScheme)` hoeven uit te lezen in elke view.

`bgApp.ignoresSafeArea()` zal automatisch in de juiste kleur paint in beide modes. Geen extra werk in views.

## Acceptance criteria

- [ ] App in light mode toont bone canvas, moss accents, italic serif "Lorre" wordmark, mono hero timer.
- [ ] App in dark mode toont forest canvas, sage accents, alle elementen leesbaar zonder bijwerken.
- [ ] Live-state (recording) toont klei-oranje dot + "RECORDING" kicker + waveform — beide modes.
- [ ] Sidebar groepeert sessies in "Today / Yesterday / This week / Earlier" met italic serif headers.
- [ ] Active session in sidebar heeft 2px moss-streep links + witte/forest-paneel achtergrond.
- [ ] Alle buttons zijn pill-vormig met de nieuwe primary/secondary stijl.
- [ ] Geen functionele regressies: bestaande 49 testen blijven groen.
- [ ] Geen layoutbreuk bij smalle window-grootte (1120×760 min): de bestaande `compactWidth`/`compactHeight` checks in `AppShellView` blijven werken.
- [ ] System-appearance wissel (macOS → "Use dark menu bar / aqua") update de app direct zonder restart.

## Risico's

1. **Dynamic colors gedragen zich raar bij screenshotting.** `NSColor(name:dynamicProvider:)` resolves bij elke draw; in unit tests of snapshot-tests is dat onvoorspelbaar. We doen geen snapshot-tests dus laag risico, maar als die er ooit komen moet de helper omkunnen met een fixed appearance.
2. **Iowan Old Style is system-bundled op macOS, maar niet op iOS/iPadOS.** Lorre is `.macOS(.v14)`-only dus geen probleem; toch noteren voor toekomstige multi-platform overweging.
3. **De grote timer (56pt) is ~3× zo hoog als nu.** Het Recorder-paneel zal verticaal groeien. `AppShellView` heeft `compactHeight < 820` checks voor padding — die blijven werken, maar het paneel zelf moet niet in een fixed-height container zitten. Snel verifiëren bij implementatie.
4. **Bestaande tests bevatten geen visuele assertions** — risico van regressies in element-staat (bv. `isEdited` styling correct?) is mensenwerk. Verwijzen naar acceptance criteria voor handmatig testen.
5. **App-icon en window chrome blijven zoals ze zijn.** Visuele dissonantie tussen donker app-icon (huidig) en de Sage-identiteit; dat lossen we niet hier op.

## Open vragen

Geen op dit moment. Bij implementatie kunnen kleine onzekerheden opduiken (bv. exacte schaduwwaarden op specifieke achtergronden) — die worden in het implementatieplan opgevangen of als small follow-up commits gedaan.
