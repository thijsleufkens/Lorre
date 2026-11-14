import SwiftUI

struct AboutSettingsTab: View {
    @Environment(\.updaterModel) private var updater

    var body: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 12)

            Text("Lorre")
                .font(.custom("Iowan Old Style", size: 48).italic())
                .foregroundStyle(DS.ColorToken.serifInk)

            VStack(spacing: 2) {
                Text(versionLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let updater {
                    CheckForUpdatesButton(updater: updater)
                        .padding(.top, 6)
                }
            }

            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    Text("Powered by ").foregroundStyle(.secondary)
                    Link("FluidAudio", destination: URL(string: "https://fluidinference.com")!)
                }
                .font(.callout)
                Link("github.com/thijsleufkens/Lorre",
                     destination: URL(string: "https://github.com/thijsleufkens/Lorre")!)
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
        return "\(Strings.current.aboutVersionTitle) \(version) (\(build))"
    }
}
