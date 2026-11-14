import Foundation
import LorreCapture
import LorreCore

/// Runs the existing speech pipeline on a recorded conversation and stores the result in the
/// conversation database.
///
/// Temporary: it transcribes the mix, like the old app. Per-track processing replaces it. It works
/// through a throwaway `FileSessionStore`, the same way `transcribe` does, so the old pipeline is
/// used unchanged.
///
/// Rule: a failure never removes or rewrites a track. The conversation stays `processing` with
/// the error recorded, and can be processed again.
struct ConversationProcessor: Sendable {
    struct Options: Sendable {
        var enableDiarization = true
        var diarizationExpectedSpeakers: DiarizationSpeakerCountHint = .auto
        var languageCode: String?
        /// When set and enabled, the transcript is also exported for downstream consumers.
        var automaticExport: AutomaticMarkdownExportConfiguration?
        /// Write the transcript-only draft record once a recording has been transcribed.
        var writesDraftRecord = true
        /// Where the draft record goes; nil uses the export folder from the settings.
        var recordFolder: URL?

        init() {}

        init(settings: AppSettings) {
            enableDiarization = settings.isSpeakerDiarizationEnabled
            diarizationExpectedSpeakers = settings.diarizationExpectedSpeakerCountHint
            languageCode = settings.batchTranscriptionLanguage.languageCode
            automaticExport = settings.automaticMarkdownExport
        }
    }

    static let transcriptFileName = "transcript.md"

    let paths: LorrePaths
    let database: LorreDatabase
    let transcription: any TranscriptionService
    let diarization: any SpeakerDiarizationService

    private var store: ConversationStore { ConversationStore(database: database) }

    /// Where the readable transcript of a conversation is written.
    static func transcriptURL(for conversationId: UUID, tracks: [Track], paths: LorrePaths) -> URL {
        folder(for: conversationId, tracks: tracks, paths: paths).appendingPathComponent(transcriptFileName)
    }

    /// Everything processing produces goes into the conversation's own folder. Imported
    /// conversations keep their audio in the old store, which is read-only for new code.
    private static func folder(for conversationId: UUID, tracks: [Track], paths: LorrePaths) -> URL {
        paths.conversationFolder(conversationId)
    }

    /// Processes the conversation and returns it in its new state. Errors are recorded on the
    /// conversation and rethrown.
    @discardableResult
    func process(
        _ conversationId: UUID,
        options: Options,
        onProgress: @escaping @Sendable (ProcessingUpdate) async -> Void = { _ in }
    ) async throws -> Conversation {
        guard let conversation = try store.conversation(id: conversationId) else {
            throw LorreError.sessionNotFound
        }
        do {
            try store.setState(.processing, lastError: conversation.lastError, for: conversationId)
            let segmentCount = try await transcribe(conversation, options: options, onProgress: onProgress)
            guard segmentCount > 0 else {
                throw LorreError.processingFailed("No speech was found in the recording.")
            }
            if options.writesDraftRecord, conversation.importedAt == nil {
                // Best effort, like the automatic export: a failed draft must not fail the processing.
                let folder: (@Sendable () throws -> URL)? = options.recordFolder.map { url in { @Sendable in url } }
                _ = try? RecordExporter(database: database, folder: folder).exportDraft(conversationId)
            }
            guard let updated = try store.setState(.proposed, lastError: nil, for: conversationId) else {
                throw LorreError.sessionNotFound
            }
            return updated
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            try? store.setState(.processing, lastError: message, for: conversationId)
            throw error
        }
    }

    private func transcribe(
        _ conversation: Conversation,
        options: Options,
        onProgress: @escaping @Sendable (ProcessingUpdate) async -> Void
    ) async throws -> Int {
        let tracks = try store.tracks(conversationId: conversation.id)
        let input = try prepareInput(for: conversation, tracks: tracks)

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("lorre-process-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let scratch = FileSessionStore(baseURL: base)

        var session = try await scratch.createSession(NewSessionDraft(
            title: conversation.title,
            folderId: nil,
            status: .processing,
            durationSeconds: conversation.durationSeconds,
            recordingSource: Self.recordingSource(for: conversation.captureSource),
            audioFileName: "audio.m4a",
            microphoneStemFileName: nil,
            systemAudioStemFileName: nil,
            recordedAt: conversation.startedAt
        ))
        let directory = await scratch.sessionDirectoryURL(for: session.id)
        let audioFileName = try await MediaAudioImporter.prepareAudio(from: input, intoDirectory: directory)
        if audioFileName != session.audioFileName {
            session.audioFileName = audioFileName
            try await scratch.updateSession(session)
        }

        var transcript = try await ProcessingCoordinator(
            store: scratch,
            transcriptionService: transcription,
            diarizationService: diarization
        ).process(
            sessionId: session.id,
            enableDiarization: options.enableDiarization,
            diarizationExpectedSpeakers: options.diarizationExpectedSpeakers,
            exportDiarizationDebugArtifact: false,
            deleteAudioAfterTranscription: false,
            languageCode: options.languageCode,
            onProgress: onProgress
        )

        // From here on the result carries the conversation's identity, not the scratch session's.
        var manifest = (try? await scratch.loadSession(id: session.id)) ?? session
        manifest.id = conversation.id
        manifest.title = conversation.title
        manifest.recordedAt = conversation.startedAt
        manifest.durationSeconds = conversation.durationSeconds ?? manifest.durationSeconds
        transcript.sessionId = conversation.id

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let segmentCount = try store.saveTranscript(
            legacyJSON: try encoder.encode(transcript),
            conversationId: conversation.id
        )
        guard segmentCount > 0 else { return 0 }

        let renderer = MarkdownExportService()
        let folder = Self.folder(for: conversation.id, tracks: tracks, paths: paths)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(renderer.render(session: manifest, transcript: transcript).utf8)
            .write(to: folder.appendingPathComponent(Self.transcriptFileName), options: .atomic)

        if let export = options.automaticExport, export.isEnabled, export.folderURL != nil {
            // Best effort: a failed export must not undo a finished transcript.
            _ = try? await AutomaticExporter.writeEnvelope(
                session: manifest, transcript: transcript, configuration: export, exporter: renderer
            )
        }
        return segmentCount
    }

    /// The audio file to transcribe: an existing mix, a fresh mix of microphone and system audio,
    /// or the only track there is.
    private func prepareInput(for conversation: Conversation, tracks: [Track]) throws -> URL {
        func url(_ kind: TrackKind) -> URL? {
            guard let track = tracks.first(where: { $0.kind == kind }) else { return nil }
            let url = paths.root.appendingPathComponent(track.relativePath)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 0 ? url : nil
        }

        if let mix = url(.mix) { return mix }
        let microphone = url(.microphone)
        let system = url(.system)

        if let microphone, let system {
            let folder = Self.folder(for: conversation.id, tracks: tracks, paths: paths)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(TrackKind.mix.fileName)
            // Written next to the tracks under a temporary name first, so a failed mix leaves no
            // half-written file that would later be mistaken for the real one.
            let partial = folder.appendingPathComponent("mix.partial.caf")
            try? FileManager.default.removeItem(at: partial)
            do {
                try RecorderAudioUtilities.mixToCanonicalFile(
                    microphoneURL: microphone, systemAudioURL: system, destinationURL: partial
                )
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: partial, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: partial)
                // One track may be damaged (an interrupted recording). The other is still worth
                // transcribing; prefer the longer one.
                let candidates = [microphone, system].map { ($0, RecordingRecovery.trackDuration($0) ?? 0) }
                guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > 0 else { throw error }
                return best.0
            }
            try store.saveTracks([Track(
                conversationId: conversation.id,
                kind: .mix,
                relativePath: paths.relativeTrackPath(conversation.id, fileName: TrackKind.mix.fileName)
            )])
            return destination
        }
        if let only = microphone ?? system { return only }
        throw LorreError.processingFailed("There is no audio to transcribe for this conversation.")
    }

    private static func recordingSource(for source: CaptureSource?) -> RecordingSource {
        switch source {
        case .systemAudio: .systemAudio
        case .microphoneAndSystemAudio: .microphoneAndSystemAudio
        case .microphone, .none: .microphone
        }
    }
}
