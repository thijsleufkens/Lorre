import Foundation
import LorreCapture
import LorreCore
import Observation

/// State behind the menu-bar recorder: start and stop a recording, and follow recent conversations
/// through processing.
@MainActor
@Observable
final class RecorderModel {
    enum Phase: Equatable {
        case idle
        case starting
        case recording(since: Date)
        case stopping
    }

    enum RowStatus: Equatable {
        case recording, waiting, processing, ready, interrupted, failed
    }

    struct Row: Identifiable, Equatable {
        var id: UUID
        var title: String
        var startedAt: Date
        var durationSeconds: Double?
        var status: RowStatus
        var error: String?
        /// The readable transcript, when there is one on disk.
        var transcriptURL: URL?
    }

    static let sourceDefaultsKey = "recorder.captureSource"
    static let recentLimit = 5

    private(set) var phase: Phase = .idle
    private(set) var levels: [TrackKind: Double] = [:]
    private(set) var rows: [Row] = []
    /// Something the user should read: a failed start, a recovered recording.
    var message: String?

    var source: CaptureSource {
        didSet { defaults.set(source.rawValue, forKey: Self.sourceDefaultsKey) }
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var isBusy: Bool { phase != .idle }

    private let paths: LorrePaths
    private let store: ConversationStore
    private let coordinator: RecordingCoordinator
    private let queue: ProcessingQueue
    private let defaults: UserDefaults
    private let notify: @Sendable (_ title: String, _ body: String) -> Void
    private var levelTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?

    init(
        paths: LorrePaths,
        database: LorreDatabase,
        coordinator: RecordingCoordinator,
        queue: ProcessingQueue,
        defaults: UserDefaults = .standard,
        notify: @escaping @Sendable (_ title: String, _ body: String) -> Void = { _, _ in }
    ) {
        self.paths = paths
        self.store = ConversationStore(database: database)
        self.coordinator = coordinator
        self.queue = queue
        self.defaults = defaults
        self.notify = notify
        self.source = defaults.string(forKey: Self.sourceDefaultsKey).flatMap(CaptureSource.init(rawValue:))
            ?? .microphoneAndSystemAudio
    }

    /// Follows the processing queue so the list and the notifications stay current.
    func observeQueue() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self, queue] in
            for await event in await queue.events() {
                guard let self else { return }
                await self.refresh()
                if case let .finished(id, error) = event {
                    self.processingFinished(id, error: error)
                }
            }
        }
    }

    func start(source requested: CaptureSource? = nil) async {
        guard phase == .idle else { return }
        if let requested { source = requested }
        phase = .starting
        message = nil
        do {
            let conversation = try await coordinator.start(source: source)
            phase = .recording(since: conversation.startedAt)
            startLevelUpdates()
        } catch {
            phase = .idle
            message = "Could not start recording. \(Self.describe(error))"
        }
        await refresh()
    }

    func stop() async {
        guard isRecording else { return }
        phase = .stopping
        levelTask?.cancel()
        levelTask = nil
        levels = [:]
        do {
            let conversation = try await coordinator.stop()
            if conversation.state == .processing {
                await queue.enqueue(conversation.id)
            } else {
                message = conversation.lastError
            }
        } catch {
            // The audio is on disk; recovery at the next launch turns it into a conversation.
            message = "The recording was saved, but could not be registered. It will be recovered when Lorre restarts. \(Self.describe(error))"
        }
        phase = .idle
        await refresh()
    }

    /// Queues a conversation for (re)processing.
    func process(_ id: UUID) async {
        await queue.enqueue(id)
        await refresh()
    }

    /// Run once at launch: turns abandoned recordings back into conversations and queues work.
    @discardableResult
    func recoverAtLaunch(database: LorreDatabase) async -> RecoveryReport? {
        let report: RecoveryReport
        do {
            report = try RecordingRecovery(paths: paths, database: database).run()
        } catch {
            message = "Could not check for interrupted recordings. \(Self.describe(error))"
            return nil
        }
        for id in report.requeue + report.recovered + report.adopted {
            await queue.enqueue(id)
        }
        if report.foundInterruptedRecordings {
            let count = report.recovered.count + report.adopted.count
            let text = count == 1
                ? "A recording was interrupted and has been recovered. It is being transcribed now."
                : "\(count) recordings were interrupted and have been recovered. They are being transcribed now."
            message = text
            notify("Recording recovered", text)
        }
        await refresh()
        return report
    }

    func refresh() async {
        let summaries = (try? store.recentConversations(limit: Self.recentLimit)) ?? []
        let current = await queue.current
        let waiting = Set(await queue.waiting)
        rows = summaries.map { summary in
            let conversation = summary.conversation
            let status: RowStatus = switch conversation.state {
            case .recording: .recording
            case .interrupted: waiting.contains(conversation.id) ? .waiting
                : (current == conversation.id ? .processing : .interrupted)
            case .processing:
                if current == conversation.id { .processing }
                else if waiting.contains(conversation.id) { .waiting }
                else { conversation.lastError == nil ? .waiting : .failed }
            case .proposed, .approved, .changed: .ready
            }
            let tracks = (try? store.tracks(conversationId: conversation.id)) ?? []
            let transcript = ConversationProcessor.transcriptURL(for: conversation.id, tracks: tracks, paths: paths)
            let hasTranscript = FileManager.default.fileExists(atPath: transcript.path(percentEncoded: false))
            return Row(
                id: conversation.id,
                title: conversation.title,
                startedAt: conversation.startedAt,
                durationSeconds: conversation.durationSeconds,
                status: status,
                error: conversation.lastError,
                transcriptURL: hasTranscript ? transcript : nil
            )
        }
    }

    private func processingFinished(_ id: UUID, error: String?) {
        let title = rows.first { $0.id == id }?.title ?? "Your conversation"
        if let error {
            notify("Transcription failed", "\(title): \(error)")
        } else {
            notify("Your conversation is ready", title)
        }
    }

    private func startLevelUpdates() {
        levelTask?.cancel()
        levelTask = Task { [weak self, coordinator] in
            while !Task.isCancelled {
                let levels = await coordinator.levels()
                guard let self, !Task.isCancelled else { return }
                self.levels = levels
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
