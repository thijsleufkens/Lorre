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

        let ext = sanitizedExtension(inputURL.pathExtension)
        let draft = NewSessionDraft(
            title: inputURL.deletingPathExtension().lastPathComponent,
            folderId: nil,
            status: .processing,
            durationSeconds: nil,
            recordingSource: .microphone,
            audioFileName: "audio.\(ext)",
            microphoneStemFileName: nil,
            systemAudioStemFileName: nil,
            recordedAt: Date()
        )
        let session = try await store.createSession(draft)
        let dir = await store.sessionDirectoryURL(for: session.id)
        let dest = dir.appendingPathComponent(session.audioFileName)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: inputURL, to: dest)

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

    private func sanitizedExtension(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sanitized = String(lower.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        return sanitized.isEmpty ? "m4a" : sanitized
    }
}
