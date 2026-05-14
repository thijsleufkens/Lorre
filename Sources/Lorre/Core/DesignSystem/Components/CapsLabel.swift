import SwiftUI

struct CapsLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(DS.FontStyle.kicker)
            .tracking(1.5)
            .foregroundStyle(DS.ColorToken.accentPrimary)
    }
}
