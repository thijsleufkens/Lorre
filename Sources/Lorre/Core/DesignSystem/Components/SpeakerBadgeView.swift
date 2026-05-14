import SwiftUI

struct SpeakerBadgeView: View {
    let speakerID: String
    let variant: SpeakerBadgeVariant

    var body: some View {
        Text(speakerID)
            .font(DS.FontStyle.control)
            .foregroundStyle(foreground)
            .padding(.horizontal, DS.Space.x2)
            .padding(.vertical, DS.Space.x1)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
            .overlay {
                switch variant {
                case .filled:
                    Capsule(style: .continuous)
                        .stroke(DS.ColorToken.black, lineWidth: 0)
                case .outline:
                    Capsule(style: .continuous)
                        .stroke(DS.ColorToken.borderSoft, lineWidth: 1)
                case .doubleOutline:
                    Capsule(style: .continuous)
                        .stroke(DS.ColorToken.borderSoft, lineWidth: 1)
                        .padding(1.5)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(DS.ColorToken.borderSoft, lineWidth: 1)
                                .padding(3)
                        )
                case .dashed:
                    Capsule(style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .foregroundStyle(DS.ColorToken.borderSoft)
                }
            }
    }

    private var fill: Color {
        variant == .filled ? DS.ColorToken.accentPrimary : DS.ColorToken.bgPanel
    }

    private var foreground: Color {
        switch variant {
        case .filled:
            return DS.ColorToken.onAccent
        case .outline, .doubleOutline:
            return DS.ColorToken.accentPrimary
        case .dashed:
            return DS.ColorToken.fgSecondary
        }
    }
}
