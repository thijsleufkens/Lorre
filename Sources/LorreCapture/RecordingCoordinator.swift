import Foundation
import LorreCore

/// Ties the capture engine to the store so that a recording exists, on disk and in the database,
/// from the moment it starts.
///
/// Rule: nothing here deletes audio. The only removal is of the empty folder when the engine could
/// not start at all.
public actor RecordingCoordinator {
    private let paths: LorrePaths
    private let store: ConversationStore
    private let engine: any CaptureEngine
    private let now: @Sendable () -> Date

    public private(set) var active: Conversation?

    public init(
        paths: LorrePaths,
        database: LorreDatabase,
        engine: any CaptureEngine,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.paths = paths
        self.store = ConversationStore(database: database)
        self.engine = engine
        self.now = now
    }

    public static func defaultTitle(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy 'at' HH:mm"
        return "Conversation \(formatter.string(from: date))"
    }

    /// Creates the conversation and its folder, then starts capturing into it.
    public func start(
        source: CaptureSource, title: String? = nil, calendarEventId: String? = nil
    ) async throws -> Conversation {
        guard active == nil else { throw CaptureError.alreadyRecording }

        let startedAt = now()
        var conversation = Conversation(
            title: title ?? Self.defaultTitle(for: startedAt),
            state: .recording,
            startedAt: startedAt,
            calendarEventId: calendarEventId,
            createdAt: startedAt,
            updatedAt: startedAt,
            captureSource: source
        )
        let folder = paths.conversationFolder(conversation.id)
        let tracks = source.trackKinds.map { kind in
            Track(
                conversationId: conversation.id,
                kind: kind,
                relativePath: paths.relativeTrackPath(conversation.id, fileName: kind.fileName)
            )
        }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try store.save(conversation)
            try store.saveTracks(tracks)
            try RecordingLock.write(in: folder, startedAt: startedAt)
            let start = try await engine.start(source: source, into: folder)
            if start.startedAt != startedAt {
                conversation.startedAt = start.startedAt
                try? store.save(conversation)
            }
        } catch {
            // Nothing has been captured yet, so there is nothing to keep.
            try? store.delete(conversationId: conversation.id)
            RecordingLock.remove(in: folder)
            Self.removeIfEmpty(folder)
            throw error
        }

        active = conversation
        return conversation
    }

    /// Stops capturing and hands the conversation over for processing.
    ///
    /// The audio is on disk before anything else happens. If the database cannot be updated the
    /// error is thrown, and the conversation is picked up by recovery at the next launch.
    public func stop() async throws -> Conversation {
        guard var conversation = active else { throw CaptureError.notRecording }
        let folder = paths.conversationFolder(conversation.id)

        let result = await engine.stop()
        active = nil
        RecordingLock.remove(in: folder)

        let kinds = conversation.captureSource?.trackKinds ?? []
        // A track of pure digital silence is a file with nothing in it worth transcribing.
        let hasAudio = kinds.contains { kind in
            !result.silentTracks.contains(kind) && Self.fileHasAudio(folder.appendingPathComponent(kind.fileName))
        }
        let microphoneWasSilent = result.silentTracks.contains(.microphone)
        let failures = result.trackFailures
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue): \($0.value)" }

        conversation.durationSeconds = result.durationSeconds
        conversation.updatedAt = now()
        if hasAudio {
            conversation.state = .processing
            if !failures.isEmpty {
                conversation.lastError = "Part of the recording could not be written (\(failures.joined(separator: "; ")))."
            } else if microphoneWasSilent {
                conversation.lastError = "Your own voice was not recorded. " + CaptureAdvice.silentMicrophone
            } else {
                conversation.lastError = nil
            }
        } else {
            conversation.state = .interrupted
            if microphoneWasSilent {
                conversation.lastError = CaptureAdvice.silentMicrophone
            } else if failures.isEmpty {
                conversation.lastError = "No audio was captured."
            } else {
                conversation.lastError = "No audio was captured (\(failures.joined(separator: "; ")))."
            }
        }
        try store.save(conversation)
        return conversation
    }

    public func levels() async -> [TrackKind: Double] {
        await engine.levels()
    }

    public func silentTracks() async -> Set<TrackKind> {
        await engine.silentTracks()
    }

    /// More than a bare file header. A system-audio track stays this small when nothing played.
    static func fileHasAudio(_ url: URL) -> Bool {
        fileSize(url) > 8192
    }

    static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func removeIfEmpty(_ folder: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        // Remove only what a failed start can leave: zero-length track files.
        let leftovers = contents.filter { name in
            fileSize(folder.appendingPathComponent(name)) > 0
        }
        guard leftovers.isEmpty else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
