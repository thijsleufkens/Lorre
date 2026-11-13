import AVFoundation
import Foundation
import LorreCore

public struct RecoveryReport: Equatable, Sendable {
    /// Conversations that were still marked as recording and are now `interrupted`.
    public var recovered: [UUID] = []
    /// Folders with audio that had no conversation; one was created for each.
    public var adopted: [UUID] = []
    /// Conversations that were waiting to be processed and should be queued again.
    public var requeue: [UUID] = []
    /// Conversations being recorded right now by a running process; left alone.
    public var stillLive: [UUID] = []

    public init() {}

    public var foundInterruptedRecordings: Bool { !recovered.isEmpty || !adopted.isEmpty }
}

/// Finds recordings that were abandoned (crash, force-quit, power loss) and makes them
/// ordinary conversations again. Run once at launch. It never deletes or rewrites audio.
public struct RecordingRecovery: Sendable {
    private let paths: LorrePaths
    private let database: LorreDatabase
    private let now: @Sendable () -> Date

    public init(paths: LorrePaths, database: LorreDatabase, now: @escaping @Sendable () -> Date = { Date() }) {
        self.paths = paths
        self.database = database
        self.now = now
    }

    public func run() throws -> RecoveryReport {
        let store = ConversationStore(database: database)
        var report = RecoveryReport()

        for conversation in try store.conversations(inStates: [.recording]) {
            let folder = paths.conversationFolder(conversation.id)
            if RecordingLock.isLive(in: folder) {
                report.stillLive.append(conversation.id)
                continue
            }
            RecordingLock.remove(in: folder)
            var updated = conversation
            updated.state = .interrupted
            updated.durationSeconds = Self.longestTrackDuration(in: folder) ?? conversation.durationSeconds
            updated.lastError = "The recording was interrupted before it was stopped."
            updated.updatedAt = now()
            try store.save(updated)
            report.recovered.append(conversation.id)
        }

        report.adopted = try adoptOrphanFolders(store: store, skipping: Set(report.stillLive))
        report.requeue = try store.conversations(inStates: [.processing]).map(\.id)
        return report
    }

    /// A folder with audio but no conversation can only come from a lost or replaced database.
    private func adoptOrphanFolders(store: ConversationStore, skipping live: Set<UUID>) throws -> [UUID] {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: paths.conversations,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var adopted: [UUID] = []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let id = UUID(uuidString: folder.lastPathComponent), !live.contains(id),
                  try store.conversation(id: id) == nil,
                  !RecordingLock.isLive(in: folder) else { continue }

            let kinds = [TrackKind.microphone, .system, .mix].filter { kind in
                RecordingCoordinator.fileSize(folder.appendingPathComponent(kind.fileName)) > 0
            }
            guard !kinds.isEmpty else { continue }

            let created = kinds
                .compactMap { try? folder.appendingPathComponent($0.fileName).resourceValues(forKeys: [.creationDateKey]).creationDate }
                .min() ?? now()
            let source: CaptureSource? = switch (kinds.contains(.microphone), kinds.contains(.system)) {
            case (true, true): .microphoneAndSystemAudio
            case (true, false): .microphone
            case (false, true): .systemAudio
            case (false, false): nil
            }
            try store.save(Conversation(
                id: id,
                title: RecordingCoordinator.defaultTitle(for: created),
                state: .interrupted,
                startedAt: created,
                durationSeconds: Self.longestTrackDuration(in: folder),
                createdAt: created,
                updatedAt: now(),
                captureSource: source,
                lastError: "This recording was found on disk without a conversation and has been restored."
            ))
            try store.saveTracks(kinds.map { kind in
                Track(conversationId: id, kind: kind, relativePath: paths.relativeTrackPath(id, fileName: kind.fileName))
            })
            RecordingLock.remove(in: folder)
            adopted.append(id)
        }
        return adopted
    }

    /// Duration of the longest readable track in the folder, or nil when none can be read.
    static func longestTrackDuration(in folder: URL) -> Double? {
        TrackKind.allCases
            .compactMap { trackDuration(folder.appendingPathComponent($0.fileName)) }
            .max()
    }

    public static func trackDuration(_ url: URL) -> Double? {
        guard RecordingCoordinator.fileSize(url) > 0, let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0, file.length > 0 else { return nil }
        return Double(file.length) / sampleRate
    }
}
