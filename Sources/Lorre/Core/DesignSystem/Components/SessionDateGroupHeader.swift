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
