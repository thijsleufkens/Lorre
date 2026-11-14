import Foundation
import Observation
import Sparkle

/// Wraps Sparkle's standard updater. Only created by the app (never by the command line) and only
/// when the Info.plist carries an update configuration; see `docs/updates.md`.
@MainActor
@Observable
final class UpdaterModel {
    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    private(set) var canCheckForUpdates = false

    /// Returns nil when this build has no update configuration.
    static func makeIfConfigured(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> UpdaterModel? {
        guard UpdateConfiguration.from(infoDictionary: infoDictionary) != nil else { return nil }
        return UpdaterModel()
    }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
