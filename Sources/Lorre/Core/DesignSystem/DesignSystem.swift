import AppKit
import SwiftUI

enum DS {
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

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    enum Space {
        static let x1: CGFloat = 4
        static let x1_5: CGFloat = 6
        static let x2: CGFloat = 8
        static let x2_5: CGFloat = 10
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x6: CGFloat = 24
        static let x8: CGFloat = 32
    }

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
}

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

extension View {
    func dsPanelSurface(selected: Bool = false, alt: Bool = false, cornerRadius: CGFloat = DS.Radius.md) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(selected ? DS.ColorToken.bgPanel : (alt ? DS.ColorToken.bgPanelAlt : DS.ColorToken.bgPanel))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(selected ? DS.ColorToken.borderStrong : DS.ColorToken.borderSoft, lineWidth: 1)
            )
    }
}

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
