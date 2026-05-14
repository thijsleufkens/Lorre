# Studio Sage Design Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh Lorre's visual identity to the "Studio Sage" design (bone/forest canvas, moss primary, clay live state, italic serif voice, dark mode parity) without changing any behavior or flow.

**Architecture:** Centralize all visual change in `DesignSystem.swift` via dynamic NSColor tokens + new typography/radii/shadow primitives + a renamed pill button style. Apply the new tokens across every existing SwiftUI view, plus add two new presentational components: a "Lorre" wordmark and date-grouping headers for the session sidebar.

**Tech Stack:** SwiftUI (macOS 14+), XCTest, Swift Package Manager. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-14-studio-sage-design.md`

**Branch:** `claude/studio-sage-design` (already created)

---

## Toolchain note

Package requires `swift-tools-version: 6.3`. If your local Swift is older (e.g., Xcode 6.2.x):
1. Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test/build` for commands below.
2. If 6.3 is still unavailable, temporarily edit `Package.swift` to `// swift-tools-version: 6.2` while iterating (revert before final commit). The features used here are 6.2-compatible.

All commands below use plain `swift test` / `swift build` for readability — adapt as needed.

---

## Task 1: Add `Color.dynamic(light:dark:)` helper

**Files:**
- Modify: `Sources/Lorre/Core/DesignSystem/DesignSystem.swift`

- [ ] **Step 1: Add `AppKit` import and dynamic-color helper**

At top of `DesignSystem.swift`, add `import AppKit` next to `import SwiftUI`. Append the helper to the `extension Color` block (replacing the existing block):

```swift
import AppKit
import SwiftUI

// ... (existing DS enum stays for now)

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lorre/Core/DesignSystem/DesignSystem.swift
git commit -m "Add Color.dynamic helper for appearance-aware tokens"
```

---

## Task 2: Test-drive `SessionDateGrouper`

**Files:**
- Create: `Sources/Lorre/Core/DesignSystem/Components/SessionDateGrouping.swift`
- Create: `Tests/LorreTests/SessionDateGroupingTests.swift`

The grouper is the only piece of new logic that warrants TDD — everything else is visual application.

- [ ] **Step 1: Write the failing tests**

Create `Tests/LorreTests/SessionDateGroupingTests.swift`:

```swift
import Foundation
import XCTest
@testable import Lorre

final class SessionDateGroupingTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return c
    }()

    private func now() -> Date {
        // 2026-05-14 14:00 in Europe/Amsterdam
        var components = DateComponents()
        components.year = 2026; components.month = 5; components.day = 14
        components.hour = 14; components.minute = 0
        components.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        return calendar.date(from: components)!
    }

    private func makeSession(name: String, daysAgo: Int, hour: Int = 10) -> SessionManifest {
        let recorded = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now())!)!
        return SessionManifest(
            title: name,
            status: .ready,
            recordedAt: recorded,
            audioFileName: nil
        )
    }

    func testEmptyListProducesNoGroups() {
        let grouper = SessionDateGrouper(calendar: calendar, now: now())
        XCTAssertTrue(grouper.group([]).isEmpty)
    }

    func testGroupsTodayYesterdayThisWeekAndEarlierInOrder() {
        let grouper = SessionDateGrouper(calendar: calendar, now: now())
        let sessions = [
            makeSession(name: "Earlier-2", daysAgo: 14),
            makeSession(name: "Today-1", daysAgo: 0),
            makeSession(name: "Week-1", daysAgo: 3),
            makeSession(name: "Yesterday-1", daysAgo: 1),
            makeSession(name: "Earlier-1", daysAgo: 9),
            makeSession(name: "Week-2", daysAgo: 5),
        ]

        let groups = grouper.group(sessions)
        let labels = groups.map(\.group)
        XCTAssertEqual(labels, [.today, .yesterday, .thisWeek, .earlier])

        XCTAssertEqual(groups[0].sessions.map(\.title), ["Today-1"])
        XCTAssertEqual(groups[1].sessions.map(\.title), ["Yesterday-1"])
        XCTAssertEqual(groups[2].sessions.map(\.title), ["Week-1", "Week-2"])
        XCTAssertEqual(groups[3].sessions.map(\.title), ["Earlier-2", "Earlier-1"])
    }

    func testPreservesInputOrderWithinGroup() {
        let grouper = SessionDateGrouper(calendar: calendar, now: now())
        let sessions = [
            makeSession(name: "A", daysAgo: 0, hour: 9),
            makeSession(name: "B", daysAgo: 0, hour: 15),
            makeSession(name: "C", daysAgo: 0, hour: 12),
        ]
        let groups = grouper.group(sessions)
        XCTAssertEqual(groups.first?.sessions.map(\.title), ["A", "B", "C"])
    }

    func testDaySixIsThisWeekAndDaySevenIsEarlier() {
        let grouper = SessionDateGrouper(calendar: calendar, now: now())
        let sessions = [
            makeSession(name: "Day6", daysAgo: 6),
            makeSession(name: "Day7", daysAgo: 7),
        ]
        let groups = grouper.group(sessions)
        let map = Dictionary(uniqueKeysWithValues: groups.map { ($0.group, $0.sessions.map(\.title)) })
        XCTAssertEqual(map[.thisWeek], ["Day6"])
        XCTAssertEqual(map[.earlier], ["Day7"])
    }

    func testEmptyGroupsAreOmitted() {
        let grouper = SessionDateGrouper(calendar: calendar, now: now())
        let sessions = [
            makeSession(name: "Today", daysAgo: 0),
            makeSession(name: "Earlier", daysAgo: 30),
        ]
        let groups = grouper.group(sessions)
        XCTAssertEqual(groups.map(\.group), [.today, .earlier])
    }
}
```

- [ ] **Step 2: Run the failing test**

Run: `swift test --filter SessionDateGroupingTests`
Expected: FAIL — "no such module" or "cannot find SessionDateGrouper in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/Lorre/Core/DesignSystem/Components/SessionDateGrouping.swift`:

```swift
import Foundation

enum SessionDateGroup: Hashable {
    case today
    case yesterday
    case thisWeek
    case earlier
}

struct SessionDateGrouper {
    struct Bucket {
        let group: SessionDateGroup
        let sessions: [SessionManifest]
    }

    let calendar: Calendar
    let now: Date

    func group(_ sessions: [SessionManifest]) -> [Bucket] {
        var today: [SessionManifest] = []
        var yesterday: [SessionManifest] = []
        var thisWeek: [SessionManifest] = []
        var earlier: [SessionManifest] = []

        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfWeekWindow = calendar.date(byAdding: .day, value: -6, to: startOfToday)!

        for session in sessions {
            let recorded = session.recordedAt ?? session.updatedAt
            let startOfRecorded = calendar.startOfDay(for: recorded)
            if startOfRecorded >= startOfToday {
                today.append(session)
            } else if startOfRecorded >= startOfYesterday {
                yesterday.append(session)
            } else if startOfRecorded >= startOfWeekWindow {
                thisWeek.append(session)
            } else {
                earlier.append(session)
            }
        }

        var result: [Bucket] = []
        if !today.isEmpty { result.append(.init(group: .today, sessions: today)) }
        if !yesterday.isEmpty { result.append(.init(group: .yesterday, sessions: yesterday)) }
        if !thisWeek.isEmpty { result.append(.init(group: .thisWeek, sessions: thisWeek)) }
        if !earlier.isEmpty { result.append(.init(group: .earlier, sessions: earlier)) }
        return result
    }
}
```

- [ ] **Step 4: Update the test helper to read `Bucket`**

The tests above use `groups[0].sessions` and `groups[0].group` — already aligned with the `Bucket` struct. No change needed.

- [ ] **Step 5: Run the tests**

Run: `swift test --filter SessionDateGroupingTests`
Expected: 5/5 pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Lorre/Core/DesignSystem/Components/SessionDateGrouping.swift Tests/LorreTests/SessionDateGroupingTests.swift
git commit -m "Add SessionDateGrouper with Today/Yesterday/Week/Earlier buckets"
```

---

## Task 3: Rewrite `DS.ColorToken` with light/dark Studio Sage palette

**Files:**
- Modify: `Sources/Lorre/Core/DesignSystem/DesignSystem.swift`

- [ ] **Step 1: Replace the `ColorToken` enum body**

Replace the entire existing `enum ColorToken { ... }` block inside `enum DS` with:

```swift
    enum ColorToken {
        // Canvas
        static let bgApp = Color.dynamic(light: Color(hex: 0xF1EDE2), dark: Color(hex: 0x0E1411))
        static let bgPanel = Color.dynamic(light: Color(hex: 0xE5DECB), dark: Color(hex: 0x0A0F0C))
        static let bgPanelAlt = Color.dynamic(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x131B17))

        // Foreground
        static let fgPrimary = Color.dynamic(light: Color(hex: 0x1F2A24), dark: Color(hex: 0xE5DECB))
        static let fgSecondary = Color.dynamic(light: Color(hex: 0x6F7A6A), dark: Color(hex: 0x7A8576))
        static let fgTertiary = Color.dynamic(light: Color(hex: 0x8A937F), dark: Color(hex: 0x5C6657))

        // Accent
        static let accentPrimary = Color.dynamic(light: Color(hex: 0x4A5D44), dark: Color(hex: 0x8FA688))
        static let accentLive = Color.dynamic(light: Color(hex: 0xCB6F4E), dark: Color(hex: 0xE08667))
        static let serifInk = Color.dynamic(light: Color(hex: 0x4A5D44), dark: Color(hex: 0x8FA688))

        // Borders
        static let borderSoft = Color.dynamic(light: Color(hex: 0xD8CFB9), dark: Color(hex: 0x1F2A22))
        static let borderStrong = Color.dynamic(light: Color(hex: 0xC2C9B5), dark: Color(hex: 0x2A372D))

        // Field surfaces
        static let fieldBg = bgPanelAlt
        static let fieldBorder = borderSoft
        static let fieldText = fgPrimary
        static let fieldPlaceholder = fgSecondary

        // Chip surfaces
        static let chipBg = bgPanel
        static let chipBorder = borderSoft

        // Utility (on-accent text colors — used by PillButtonStyle)
        static let onAccent = bgApp
        static let black = Color(hex: 0x111111)
        static let white = Color(hex: 0xFFFFFF)

        // Status
        static let statusReady = accentPrimary
        static let statusPreparing = Color.dynamic(light: Color(hex: 0xB8893A), dark: Color(hex: 0xC29B3E))
        static let statusError = Color.dynamic(light: Color(hex: 0xB33F2A), dark: Color(hex: 0xE08667))
        static let statusIdle = fgTertiary
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete. All existing `DS.ColorToken.xxx` call sites still resolve.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lorre/Core/DesignSystem/DesignSystem.swift
git commit -m "Switch DS.ColorToken to dynamic Studio Sage palette"
```

---

## Task 4: Rewrite `DS.FontStyle` for the Sage typography stack

**Files:**
- Modify: `Sources/Lorre/Core/DesignSystem/DesignSystem.swift`

- [ ] **Step 1: Replace the `FontStyle` enum body**

Replace the entire existing `enum FontStyle { ... }` block with:

```swift
    enum FontStyle {
        // Brand voice (italic serif)
        static let wordmark = Font.custom("Iowan Old Style", size: 22).italic()
        static let sectionLabel = Font.custom("Iowan Old Style", size: 13).italic()
        static let groupHead = Font.custom("Iowan Old Style", size: 12).italic()

        // UI sans (system SF Pro)
        static let appTitle = Font.system(size: 22, weight: .semibold)
        static let panelTitle = Font.system(size: 26, weight: .semibold).leading(.tight)
        static let body = Font.system(size: 13, weight: .regular)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let control = Font.system(size: 12, weight: .semibold)
        static let helper = Font.system(size: 11, weight: .regular)
        static let kicker = Font.system(size: 11, weight: .semibold)
        static let stageStatus = kicker

        // Mono (system SF Mono)
        static let timer = Font.system(size: 56, weight: .medium, design: .monospaced)
        static let timerCompact = Font.system(size: 18, weight: .semibold, design: .monospaced)
        static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let monoStrong = Font.system(size: 12, weight: .semibold, design: .monospaced)
    }
```

Note: `stageStatus` is aliased to `kicker` to keep existing call sites working unchanged.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lorre/Core/DesignSystem/DesignSystem.swift
git commit -m "Refresh DS.FontStyle: italic-serif voice + SF system stack"
```

---

## Task 5: Update `DS.Radius` + add new shadow modifiers

**Files:**
- Modify: `Sources/Lorre/Core/DesignSystem/DesignSystem.swift`

- [ ] **Step 1: Replace the `Radius` enum and append shadow modifiers**

Replace `enum Radius` with:

```swift
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }
```

At the bottom of the file (after the existing `extension View` block), append:

```swift
extension View {
    func dsSurfaceShadow() -> some View {
        shadow(color: Color.black.opacity(0.10), radius: 3, x: 0, y: 1)
    }

    func dsPanelShadow() -> some View {
        self
            .shadow(color: Color.black.opacity(0.07), radius: 24, x: 0, y: 8)
            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lorre/Core/DesignSystem/DesignSystem.swift
git commit -m "Tighten radii (md=10, lg=14, pill=999) and add shadow modifiers"
```

---

## Task 6: Rewrite primary/secondary button styles as pills

**Files:**
- Modify: `Sources/Lorre/Core/DesignSystem/DesignSystem.swift`

Replace the existing `PrimaryControlButtonStyle` and `SecondaryControlButtonStyle` structs (keep names so call sites don't change).

- [ ] **Step 1: Replace both ButtonStyle structs**

Find the existing `struct SecondaryControlButtonStyle: ButtonStyle { ... }` and `struct PrimaryControlButtonStyle: ButtonStyle { ... }` blocks. Replace both with:

```swift
struct PrimaryControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .font(DS.FontStyle.control)
            .foregroundStyle(isEnabled ? DS.ColorToken.onAccent : DS.ColorToken.fgTertiary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isEnabled
                            ? DS.ColorToken.accentPrimary.opacity(pressed ? 0.85 : 1)
                            : DS.ColorToken.bgPanelAlt
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isEnabled ? Color.clear : DS.ColorToken.borderSoft, lineWidth: 1)
            )
    }
}

struct SecondaryControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .font(DS.FontStyle.control)
            .foregroundStyle(isEnabled ? DS.ColorToken.fgPrimary : DS.ColorToken.fgTertiary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(pressed ? DS.ColorToken.bgPanel : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(DS.ColorToken.borderSoft, lineWidth: 1)
            )
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete. All existing call sites (`.buttonStyle(PrimaryControlButtonStyle())`, etc.) still compile.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lorre/Core/DesignSystem/DesignSystem.swift
git commit -m "Convert primary/secondary control buttons to pill style"
```

---

## Task 7: Update `.dsPanelSurface()` + add `.dsActiveAccentBar()`

**Files:**
- Modify: `Sources/Lorre/Core/DesignSystem/DesignSystem.swift`

- [ ] **Step 1: Replace the existing `extension View { func dsPanelSurface ... }`**

Replace the existing `dsPanelSurface` extension with:

```swift
extension View {
    func dsPanelSurface(
        selected: Bool = false,
        alt: Bool = false,
        cornerRadius: CGFloat = DS.Radius.lg
    ) -> some View {
        let fill: Color = {
            if selected { return DS.ColorToken.bgPanelAlt }
            return alt ? DS.ColorToken.bgPanel : DS.ColorToken.bgPanelAlt
        }()
        return self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(selected ? DS.ColorToken.borderStrong : DS.ColorToken.borderSoft, lineWidth: 1)
            )
    }

    func dsActiveAccentBar(isActive: Bool, cornerRadius: CGFloat = DS.Radius.md) -> some View {
        overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(DS.ColorToken.accentPrimary)
                    .frame(width: 2)
                    .padding(.vertical, 4)
                    .padding(.leading, 1)
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lorre/Core/DesignSystem/DesignSystem.swift
git commit -m "Update dsPanelSurface to bone/forest fills and add dsActiveAccentBar"
```

---

## Task 8: Add `LorreWordmark` view

**Files:**
- Create: `Sources/Lorre/Core/DesignSystem/Components/LorreWordmark.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

struct LorreWordmark: View {
    var body: some View {
        Text("Lorre")
            .font(DS.FontStyle.wordmark)
            .foregroundStyle(DS.ColorToken.serifInk)
            .accessibilityAddTraits(.isHeader)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lorre/Core/DesignSystem/Components/LorreWordmark.swift
git commit -m "Add LorreWordmark view (italic serif brandmark)"
```

---

## Task 9: Add `SessionDateGroupHeader` view

**Files:**
- Create: `Sources/Lorre/Core/DesignSystem/Components/SessionDateGroupHeader.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

struct SessionDateGroupHeader: View {
    let group: SessionDateGroup

    var body: some View {
        Text("— " + label)
            .font(DS.FontStyle.groupHead)
            .foregroundStyle(DS.ColorToken.serifInk)
            .padding(.horizontal, DS.Space.x2)
            .padding(.top, DS.Space.x3)
            .padding(.bottom, DS.Space.x1)
    }

    private var label: String {
        switch group {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This week"
        case .earlier: return "Earlier"
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lorre/Core/DesignSystem/Components/SessionDateGroupHeader.swift
git commit -m "Add SessionDateGroupHeader view"
```

---

## Task 10: Update existing DS components

**Files:**
- Modify: `Sources/Lorre/Core/DesignSystem/Components/IndexRailView.swift`
- Modify: `Sources/Lorre/Core/DesignSystem/Components/SearchFieldView.swift`
- Modify: `Sources/Lorre/Core/DesignSystem/Components/SpeakerBadgeView.swift`

Open each file, read it in full, then apply these patterns. These are mechanical token swaps — verify before/after by re-reading each file after edits.

- [ ] **Step 1: `IndexRailView`**

Read the file. Replace any usages following these patterns:
- Dots/markers using `DS.ColorToken.borderStrong` → `DS.ColorToken.accentPrimary`
- The "live" or active dot color → `DS.ColorToken.accentLive`
- Vertical rail line color: keep `DS.ColorToken.borderSoft`

If the file uses CapsLabel-style headings, keep them — the font has already been updated in Task 4.

- [ ] **Step 2: `SearchFieldView`**

Read the file. Apply:
- Background fill: `DS.ColorToken.fieldBg` (already maps correctly to new tokens, no change needed unless a literal Color is used — replace any with `DS.ColorToken.fieldBg`).
- Border: `DS.ColorToken.fieldBorder` (idem).
- Placeholder font: `DS.FontStyle.helper`.
- Corner radius: `DS.Radius.sm` (8 — keep).

- [ ] **Step 3: `SpeakerBadgeView`**

Read the file. Apply:
- Default (unfilled) variant: `bgPanel` fill, `accentPrimary` foreground, `borderSoft` stroke.
- Filled / user-renamed variant: `accentPrimary` fill, `onAccent` foreground.
- Dashed (unknown speaker) variant: `borderSoft` dashed stroke, `fgSecondary` foreground.
- Font: `DS.FontStyle.helper` or `kicker` depending on context — match existing usage.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 5: Run full test suite**

Run: `swift test`
Expected: All existing tests pass (49 + 5 new = 54).

- [ ] **Step 6: Commit**

```bash
git add Sources/Lorre/Core/DesignSystem/Components/
git commit -m "Update IndexRail, SearchField, SpeakerBadge to Sage tokens"
```

---

## Task 11: Update `LorreApp.swift`

**Files:**
- Modify: `Sources/Lorre/App/LorreApp.swift`

- [ ] **Step 1: Add appearance-following modifier**

Replace the `WindowGroup` body with:

```swift
        WindowGroup("Lorre") {
            AppShellView(viewModel: viewModel)
                .frame(minWidth: 1120, minHeight: 760)
                .preferredColorScheme(nil)
                .task {
                    await viewModel.start()
                }
        }
```

`.preferredColorScheme(nil)` is the default but make it explicit so it's clear the app follows system appearance.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lorre/App/LorreApp.swift
git commit -m "Explicitly follow system appearance in LorreApp"
```

---

## Task 12: Update `SessionShelfSidebarView.swift`

**Files:**
- Modify: `Sources/Lorre/Features/Shell/SessionShelfSidebarView.swift`

This view is the home for the wordmark + date grouping + new item styling. Read the file first to understand its structure (it's ~530 lines).

- [ ] **Step 1: Add wordmark at top of the sidebar**

Find the root container of `SessionShelfView`'s body (a `VStack` typically). At the very top, before the existing header/search/list elements, insert:

```swift
LorreWordmark()
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, DS.Space.x4)
    .padding(.top, DS.Space.x4)
    .padding(.bottom, DS.Space.x2)
```

- [ ] **Step 2: Apply date-grouping to the sessions list**

Locate the `ForEach` that iterates over `viewModel.sessions` (or the source-of-truth list — could be a filtered/sorted variant). Replace it with a grouped iteration:

```swift
let grouper = SessionDateGrouper(calendar: .current, now: Date())
ForEach(grouper.group(visibleSessions), id: \.group) { bucket in
    Section {
        ForEach(bucket.sessions) { session in
            sessionRow(for: session)
        }
    } header: {
        SessionDateGroupHeader(group: bucket.group)
    }
}
```

Where `visibleSessions` is the list currently displayed (rename to match what already exists) and `sessionRow(for:)` is the existing row-rendering helper extracted into a function if it isn't already. If the row body is inline, extract it as a private `func sessionRow(for session: SessionManifest) -> some View` to keep the loop readable.

- [ ] **Step 3: Apply new item styling to the session row**

In `sessionRow(for:)`, ensure the row uses:
- Background via `.dsPanelSurface(selected: isSelected)` (selected sessions get the paper-white panel, unselected ones stay transparent or get the alt-bone)
- `.dsActiveAccentBar(isActive: isSelected)` overlay for the moss-streep
- Title font: `DS.FontStyle.bodyStrong`
- Subtitle/meta font: `DS.FontStyle.helper` in `DS.ColorToken.fgSecondary`

Example row body:

```swift
HStack(alignment: .top, spacing: DS.Space.x2) {
    VStack(alignment: .leading, spacing: 2) {
        Text(session.title)
            .font(DS.FontStyle.bodyStrong)
            .foregroundStyle(DS.ColorToken.fgPrimary)
            .lineLimit(1)
        Text(metaLine(for: session))
            .font(DS.FontStyle.helper)
            .foregroundStyle(DS.ColorToken.fgSecondary)
            .lineLimit(1)
    }
    Spacer(minLength: 0)
    if session.isLiveRecording {
        Circle()
            .fill(DS.ColorToken.accentLive)
            .frame(width: 6, height: 6)
    }
}
.padding(.horizontal, DS.Space.x3)
.padding(.vertical, DS.Space.x2)
.frame(maxWidth: .infinity, alignment: .leading)
.background(
    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        .fill(isSelected ? DS.ColorToken.bgPanelAlt : Color.clear)
)
.dsActiveAccentBar(isActive: isSelected)
.contentShape(Rectangle())
.onTapGesture { viewModel.select(session) }
```

(Replace `session.isLiveRecording` with the actual property used today. If it doesn't exist as a single boolean, derive it from `viewModel.activeRecordingSessionID == session.id` or similar.)

- [ ] **Step 4: Apply pill styling to footer/action buttons**

Any "New session" or "Start recording" or "Import audio" button in the sidebar should use `.buttonStyle(PrimaryControlButtonStyle())` — this is now pill-shaped automatically. Verify each by scanning the file.

- [ ] **Step 5: Build and run all tests**

Run: `swift build && swift test`
Expected: Build clean, tests green.

- [ ] **Step 6: Commit**

```bash
git add Sources/Lorre/Features/Shell/SessionShelfSidebarView.swift
git commit -m "Apply Sage styling to sidebar: wordmark, date grouping, item polish"
```

---

## Task 13: Update `RecorderStageViews.swift`

**Files:**
- Modify: `Sources/Lorre/Features/Recorder/RecorderStageViews.swift` (~1065 lines)

This is the largest file in the visual application. The key surfaces are: the empty recorder console, the active recording panel, the processing/loading states, the imported-file recorder. All should adopt the new tokens.

- [ ] **Step 1: Hero title + kicker pattern**

Wherever a stage shows a "title + meta-line" header (typically near the top of `RecorderConsoleView` and `ProcessingPipelineView`), apply this pattern:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text("— Recorder")
        .font(DS.FontStyle.sectionLabel)
        .foregroundStyle(DS.ColorToken.serifInk)
    Text(viewModel.activeStageTitle)   // existing title binding
        .font(DS.FontStyle.panelTitle)
        .foregroundStyle(DS.ColorToken.fgPrimary)
    Text(viewModel.activeStageMeta)    // existing meta binding
        .font(DS.FontStyle.helper)
        .foregroundStyle(DS.ColorToken.fgSecondary)
}
```

Replace each existing header block with this pattern. Use the actual binding names from the existing code.

- [ ] **Step 2: Recording panel — live indicator + timer**

Find the active-recording panel (where the elapsed-time timer is shown). Apply:

```swift
VStack(alignment: .leading, spacing: DS.Space.x2) {
    HStack(spacing: DS.Space.x2) {
        Circle()
            .fill(DS.ColorToken.accentLive)
            .frame(width: 12, height: 12)
            .shadow(color: DS.ColorToken.accentLive.opacity(0.35), radius: 4, x: 0, y: 0)
        Text("RECORDING")
            .font(DS.FontStyle.kicker)
            .tracking(1.5)
            .foregroundStyle(DS.ColorToken.accentLive)
        Spacer()
        // existing Pause/Stop buttons — keep the existing PrimaryControlButtonStyle / SecondaryControlButtonStyle bindings; they are now pills automatically
    }
    Text(Formatters.duration(viewModel.recordingElapsedSeconds))
        .font(DS.FontStyle.timer)
        .foregroundStyle(DS.ColorToken.fgPrimary)
        .monospacedDigit()
}
.padding(DS.Space.x4)
.background(
    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        .fill(DS.ColorToken.bgPanelAlt)
)
.dsPanelShadow()
```

Note: the existing 18pt timer font is gone — `DS.FontStyle.timer` is now 56pt. Verify the recorder panel can grow vertically (the parent VStack in `AppShellView` has `.frame(maxHeight: .infinity)`, so it can). Test in the smallest supported window (1120×760).

- [ ] **Step 3: Waveform / level meter colors**

If a level meter or waveform exists, swap any `DS.ColorToken.fgPrimary`/`black` fills for `DS.ColorToken.accentPrimary` with opacity 0.75 in light (the dynamic token will handle dark mode automatically — the dark fallback already has its own opacity behavior in render).

- [ ] **Step 4: Source-mode chips**

Any "Microphone / System audio / Mic + System" toggle chips should use `DS.ColorToken.chipBg` fill, `DS.ColorToken.chipBorder` stroke, and `DS.FontStyle.helper` for the label. Selected variant: `DS.ColorToken.accentPrimary` fill with `DS.ColorToken.onAccent` text. The existing token names map correctly, but double-check any hardcoded colors and replace them.

- [ ] **Step 5: Empty state messaging**

Any empty-state text (e.g. "No microphone access" or "Drop a file here") uses `DS.FontStyle.body` in `DS.ColorToken.fgSecondary`.

- [ ] **Step 6: Build, test, and visually inspect the recorder**

```bash
swift build && swift test
```
Expected: Build clean, tests green.

Then build the app (`./scripts/package_macos_app.sh release` with `DEVELOPER_DIR` as needed) and launch. Verify:
- The recorder kicker shows "— Recorder" in italic serif moss
- Title appears below in 26pt semibold
- "RECORDING" kicker is clay-orange when recording
- The hero timer is large (56pt SF Mono)
- Pause/Stop are pill-shaped

- [ ] **Step 7: Commit**

```bash
git add Sources/Lorre/Features/Recorder/RecorderStageViews.swift
git commit -m "Apply Sage styling to Recorder stages: hero timer, live indicator, kicker"
```

---

## Task 14: Update Transcript views

**Files:**
- Modify: `Sources/Lorre/Features/Transcript/TranscriptViews.swift`
- Modify: `Sources/Lorre/Features/Transcript/TranscriptSegmentRowViews.swift`
- Modify: `Sources/Lorre/Features/Transcript/TranscriptHeaderComponents.swift`

- [ ] **Step 1: Transcript stage header**

In `TranscriptStageView`'s header block, apply the section-label / panelTitle / helper pattern:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text("— Transcript")
        .font(DS.FontStyle.sectionLabel)
        .foregroundStyle(DS.ColorToken.serifInk)
    Text(session.title)
        .font(DS.FontStyle.panelTitle)
        .foregroundStyle(DS.ColorToken.fgPrimary)
    Text(viewModel.transcriptMeta)  // existing meta binding — adjust to real name
        .font(DS.FontStyle.helper)
        .foregroundStyle(DS.ColorToken.fgSecondary)
}
```

- [ ] **Step 2: Segment row styling**

In `TranscriptSegmentRowViews.swift`, for each segment row:
- Speaker label uses `SpeakerBadgeView` (already restyled in Task 10)
- Time pill uses `DS.FontStyle.monoStrong` in `DS.ColorToken.fgSecondary`
- Body text uses `DS.FontStyle.body` in `DS.ColorToken.fgPrimary`
- The row container background: `Color.clear` (no per-row card) — rely on `borderSoft` 1px bottom-border for separation:

```swift
.overlay(alignment: .bottom) {
    Rectangle()
        .fill(DS.ColorToken.borderSoft)
        .frame(height: 0.5)
}
```

- Edited segments (`segment.isEdited`): apply a `borderStrong` 2px left-border and a `bgPanelAlt` subtle background highlight:

```swift
.background(
    Rectangle().fill(segment.isEdited ? DS.ColorToken.bgPanelAlt : Color.clear)
)
.overlay(alignment: .leading) {
    if segment.isEdited {
        Rectangle().fill(DS.ColorToken.borderStrong).frame(width: 2)
    }
}
```

- [ ] **Step 3: Transcript header components**

In `TranscriptHeaderComponents.swift`, any "filter chip" or "speaker filter" element uses this chip pattern:

```swift
Text(label)
    .font(DS.FontStyle.helper)
    .foregroundStyle(isSelected ? DS.ColorToken.onAccent : DS.ColorToken.fgPrimary)
    .padding(.horizontal, DS.Space.x2)
    .padding(.vertical, 4)
    .background(
        Capsule().fill(isSelected ? DS.ColorToken.accentPrimary : DS.ColorToken.chipBg)
    )
    .overlay(
        Capsule().stroke(isSelected ? Color.clear : DS.ColorToken.chipBorder, lineWidth: 1)
    )
```

Export buttons: `.buttonStyle(PrimaryControlButtonStyle())` for the main export and `.buttonStyle(SecondaryControlButtonStyle())` for "Copy" / "Open in Finder" / etc.

- [ ] **Step 4: Build and test**

```bash
swift build && swift test
```
Expected: Build clean, 54 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Lorre/Features/Transcript/
git commit -m "Apply Sage styling to Transcript views"
```

---

## Task 15: Update `AppShellView.swift`

**Files:**
- Modify: `Sources/Lorre/Features/Shell/AppShellView.swift` (~206 lines)

- [ ] **Step 1: Banner styling**

Locate `AppBannerView`. Replace its container with:

```swift
HStack(alignment: .top, spacing: DS.Space.x3) {
    // ... existing icon/text content
}
.padding(DS.Space.x3)
.background(
    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        .fill(DS.ColorToken.bgPanelAlt)
)
.overlay(
    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        .stroke(DS.ColorToken.borderSoft, lineWidth: 1)
)
.dsSurfaceShadow()
```

Keep the dismiss-button as a `SecondaryControlButtonStyle` pill.

- [ ] **Step 2: Active recording badge**

Find `ActiveRecordingBadge` (used in `ActiveRecordingWorkspaceView`). Replace its body with:

```swift
HStack(spacing: 6) {
    Circle()
        .fill(DS.ColorToken.accentLive)
        .frame(width: 6, height: 6)
    Text(label)
        .font(DS.FontStyle.kicker)
        .tracking(1.5)
        .foregroundStyle(DS.ColorToken.accentLive)
}
.padding(.horizontal, DS.Space.x2)
.padding(.vertical, 4)
.background(
    Capsule().fill(DS.ColorToken.accentLive.opacity(0.10))
)
.overlay(
    Capsule().stroke(DS.ColorToken.accentLive.opacity(0.35), lineWidth: 1)
)
```

- [ ] **Step 3: CapsLabel update (lives in same file or separately — check)**

`CapsLabel` may live in this file or in a separate file. Locate it and update its body:

```swift
Text(text.uppercased())
    .font(DS.FontStyle.kicker)
    .tracking(1.5)
    .foregroundStyle(DS.ColorToken.accentPrimary)
```

- [ ] **Step 4: Build and test**

```bash
swift build && swift test
```
Expected: Build clean, 54 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Lorre/Features/Shell/AppShellView.swift
git commit -m "Apply Sage styling to AppShellView: banner, recording badge, caps label"
```

---

## Task 16: Update remaining Shell views

**Files:**
- Modify: `Sources/Lorre/Features/Shell/SessionShelfModelSettingsView.swift`
- Modify: `Sources/Lorre/Features/Shell/SpeakerRecognitionQuickAccessView.swift`

- [ ] **Step 1: `SessionShelfModelSettingsView.swift`**

Read the file. For each section:
- Section heading: `DS.FontStyle.sectionLabel` in `DS.ColorToken.serifInk` with "— " prefix.
- Helper/description text: `DS.FontStyle.helper` in `DS.ColorToken.fgSecondary`.
- Body container: `.dsPanelSurface()` (now uses `bgPanelAlt` paper fill).
- "Save" / "Reset" buttons: `PrimaryControlButtonStyle` / `SecondaryControlButtonStyle` (now pills).
- Native pickers (Picker, Toggle): no styling changes; they pick up SwiftUI's appearance automatically.

- [ ] **Step 2: `SpeakerRecognitionQuickAccessView.swift`**

Read the file. Apply the same patterns:
- Section labels in italic serif.
- Helper text.
- Action buttons as pills.
- Speaker cards use `.dsPanelSurface()` and `SpeakerBadgeView`.

- [ ] **Step 3: Build and test**

```bash
swift build && swift test
```
Expected: Build clean, 54 tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Lorre/Features/Shell/
git commit -m "Apply Sage styling to model settings and speaker quick access"
```

---

## Task 17: Full verification — build, test, manual visual check

**Files:** (none — verification only)

- [ ] **Step 1: Full test run**

Run: `swift test`
Expected: 54/54 tests pass. If any test fails, investigate and fix before continuing.

- [ ] **Step 2: Build release `.app`**

Run: `./scripts/package_macos_app.sh release`
Expected: `dist/Lorre.app` created.

- [ ] **Step 3: Install and launch**

```bash
rm -rf /Applications/Lorre.app
cp -R dist/Lorre.app /Applications/
open /Applications/Lorre.app
```

- [ ] **Step 4: Visual acceptance check (light mode)**

System Settings → Appearance → Light. Reload the app if needed. Verify against the spec's acceptance criteria:
- Window canvas is bone (#F1EDE2)
- Sidebar has "Lorre" wordmark in italic serif moss at top
- Session items are grouped by "Today / Yesterday / This week / Earlier" with italic serif headers
- Active session has a 2px moss left-bar and paper-white background
- "— Recorder" kicker in italic serif moss, panel title in 26pt SF Pro semibold below
- "RECORDING" kicker is clay-orange when recording, hero timer is 56pt SF Mono
- Pause/Stop are pill-shaped (capsule)
- No leftover white/black-only chrome from the old design

- [ ] **Step 5: Visual acceptance check (dark mode)**

System Settings → Appearance → Dark. App should update live (no restart). Verify:
- Window canvas is forest (#0E1411)
- Wordmark, kickers, group headers are sage light (#8FA688)
- Live state and waveform clay-orange/sage all read clearly
- Borders are subtle but visible
- No "stuck light mode" elements

- [ ] **Step 6: Edge case — narrow window**

Resize the window to its minimum (1120×760). Verify:
- Recorder panel doesn't overflow vertically
- Sidebar still readable
- Compact-width branch (<1180) still applies its narrower padding

- [ ] **Step 7: If everything passes, commit a verification note**

If there are any small follow-ups discovered during visual check, fix them with small commits. Then:

```bash
git log --oneline claude/studio-sage-design ^master | wc -l
```
Expected: ~17 commits on the branch.

---

## Self-review notes (for the implementer)

If any task above leaves you with unclear bindings (e.g., "the existing title binding"), open the file and search for the comparable usage that's being replaced. The patterns are consistent — if you find a Text() with `.font(DS.FontStyle.panelTitle)` today, that's the spot.

Avoid:
- Hardcoded hex colors anywhere outside `DesignSystem.swift`.
- Hardcoded font sizes outside `DS.FontStyle`.
- New radii outside `DS.Radius`.

If you find a violation in code you're touching, fix it in the same commit.

---

## Out of plan

These were called out in the spec as out-of-scope and should not be done here:
- New features or flows
- App icon refresh
- Custom font bundling (Inter / JetBrains Mono)
- Animations / micro-interactions
- Accessibility audit

If any of those come up during implementation, file them as a follow-up (new branch / spec).
