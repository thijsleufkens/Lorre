import Foundation

/// Keeps the Mac from idle-sleeping while a recording runs.
final class SleepGuard {
    private var token: NSObjectProtocol?

    var isActive: Bool { token != nil }

    func begin(reason: String = "Recording a conversation") {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
    }

    func end() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }

    deinit { end() }
}
