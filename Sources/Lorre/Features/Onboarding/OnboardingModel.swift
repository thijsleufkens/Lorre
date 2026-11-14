import Foundation
import LorreCore
import Observation

/// State behind the first-run sheet: three short steps, then "done" is remembered in the settings.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome, name, permissions
    }

    private(set) var step: Step = .welcome
    var name: String
    /// Set once `complete()` has run; the sheet closes on it.
    private(set) var isCompleted = false
    /// Set when the answers could not be saved. The sheet still closes, so nobody is stuck on it.
    private(set) var saveFailed = false

    @ObservationIgnored private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        self.name = (try? settings.userName()) ?? ""
    }

    /// Whether the first run still has to be shown. A settings problem counts as done: the user
    /// should not be blocked by a screen that cannot be saved.
    static func isNeeded(settings: SettingsStore) -> Bool {
        do {
            return try settings.string(.onboardingDone) != "1"
        } catch {
            return false
        }
    }

    static var stepCount: Int { Step.allCases.count }

    var stepNumber: Int { step.rawValue + 1 }
    var isFirstStep: Bool { step == .welcome }
    var isLastStep: Bool { step == Step.allCases.last }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The name step needs a name; the other steps can always go on.
    var canContinue: Bool {
        step == .name ? !trimmedName.isEmpty : true
    }

    func next() {
        guard canContinue, let following = Step(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Saves the name and remembers that the first run is done.
    func complete() {
        guard !isCompleted else { return }
        do {
            if !trimmedName.isEmpty { try settings.set(trimmedName, for: .userName) }
            try settings.set("1", for: .onboardingDone)
        } catch {
            saveFailed = true
        }
        isCompleted = true
    }
}
