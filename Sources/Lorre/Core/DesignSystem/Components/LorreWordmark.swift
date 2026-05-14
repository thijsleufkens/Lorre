import SwiftUI

struct LorreWordmark: View {
    var body: some View {
        Text("Lorre")
            .font(DS.FontStyle.wordmark)
            .foregroundStyle(DS.ColorToken.serifInk)
            .accessibilityAddTraits(.isHeader)
    }
}
