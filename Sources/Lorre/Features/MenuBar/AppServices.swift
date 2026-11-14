import Foundation
import LorreCapture
import LorreCore
import UserNotifications

/// The pieces of the rebuilt app that live for the whole run: database, recorder, processing queue.
@MainActor
final class AppServices {
    let recorder: RecorderModel?
    /// State behind the main window; nil when the database could not be opened.
    let workspace: WorkspaceModel?
    /// Small settings kept in the database (export folder, the user's name).
    let settings: SettingsStore?
    /// Set when the conversation database could not be opened; recording is unavailable then.
    let startupError: String?

    init(dependencies: AppDependencies, paths: LorrePaths = LorrePaths()) {
        do {
            let database = try LorreDatabase(url: paths.database)
            let processor = ConversationProcessor(
                paths: paths,
                database: database,
                transcription: dependencies.transcription,
                diarization: dependencies.diarization
            )
            let settingsStore = dependencies.settings
            let queue = ProcessingQueue { id in
                let settings = try await settingsStore.load()
                await processor.diarization.setDiarizationEngine(settings.diarizationEngine)
                try await processor.process(id, options: .init(settings: settings))
                await ProposalRunner(database: database).run(id)
            }
            let coordinator = RecordingCoordinator(paths: paths, database: database, engine: LiveCaptureEngine())
            let model = RecorderModel(
                paths: paths,
                database: database,
                coordinator: coordinator,
                queue: queue,
                notify: Self.postNotification
            )
            recorder = model
            workspace = WorkspaceModel(database: database, paths: paths, makePlayer: { EvidencePlayer() })
            settings = SettingsStore(database: database)
            startupError = nil
            model.observeQueue()
            Task { await model.recoverAtLaunch(database: database) }
        } catch {
            recorder = nil
            workspace = nil
            settings = nil
            startupError = "Lorre could not open its database: \(error.localizedDescription)"
        }
    }

    /// Posts a plain notification. Clicking it brings Lorre forward.
    private static let postNotification: @Sendable (String, String) -> Void = { title, body in
        // UNUserNotificationCenter needs an app bundle; `swift run` has none.
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
        }
    }
}
