import ArgumentParser
import Foundation

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio or video file locally."
    )

    @Argument(help: "Path to an audio or video file.")
    var input: String

    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: inputURL.path(percentEncoded: false)) else {
            throw ValidationError("Input file not found: \(input)")
        }

        let factory = TranscribeServiceFactory()
        let settings = try await factory.settings.load()

        // Spike: throwaway temp store, audio-only copy.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("lorre-cli-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = FileSessionStore(baseURL: base)
        let coordinator = ProcessingCoordinator(
            store: store,
            transcriptionService: factory.transcription,
            diarizationService: factory.diarization
        )

        let draft = NewSessionDraft(
            title: inputURL.deletingPathExtension().lastPathComponent,
            folderId: nil,
            status: .processing,
            durationSeconds: nil,
            recordingSource: .microphone,
            audioFileName: "audio.m4a",
            microphoneStemFileName: nil,
            systemAudioStemFileName: nil,
            recordedAt: Date()
        )
        var session = try await store.createSession(draft)
        let dir = await store.sessionDirectoryURL(for: session.id)
        let audioFileName = try await MediaAudioImporter.prepareAudio(from: inputURL, intoDirectory: dir)
        if audioFileName != session.audioFileName {
            session.audioFileName = audioFileName
            session.updatedAt = Date()
            try await store.updateSession(session)
        }

        await factory.diarization.setDiarizationEngine(settings.diarizationEngine)

        let transcript = try await coordinator.process(
            sessionId: session.id,
            enableDiarization: settings.isSpeakerDiarizationEnabled,
            diarizationExpectedSpeakers: settings.diarizationExpectedSpeakerCountHint,
            exportDiarizationDebugArtifact: false,
            deleteAudioAfterTranscription: false,
            languageCode: settings.batchTranscriptionLanguage.languageCode,
            onProgress: { update in
                FileHandle.standardError.write(Data("[\(Int((update.fraction ?? 0) * 100))%] \(update.label)\n".utf8))
            }
        )

        let reloaded = (try? await store.loadSession(id: session.id)) ?? session
        let markdown = MarkdownExportService().render(session: reloaded, transcript: transcript)
        print(markdown)
    }
}
