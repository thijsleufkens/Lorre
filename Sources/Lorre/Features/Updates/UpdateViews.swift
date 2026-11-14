import SwiftUI

/// The button for the app menu and the About tab. The caller shows it only when updates are configured.
struct CheckForUpdatesButton: View {
    let updater: UpdaterModel

    var body: some View {
        Button(Strings.current.checkForUpdates) { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

extension EnvironmentValues {
    /// The updater, nil when this build has no update configuration.
    @Entry var updaterModel: UpdaterModel?
}
