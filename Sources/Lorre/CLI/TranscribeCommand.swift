import ArgumentParser
import Foundation

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio or video file locally."
    )

    @Argument(help: "Path to an audio or video file.")
    var input: String

    @Option(name: [.short, .long], help: "Output path. Omit to write to stdout. For --format both this is a path stem.")
    var out: String?

    @Option(help: "Output format: md, json, or both.")
    var format: TranscribeFormat = .md

    @Flag(help: "Persist a real Lorre session and write the md+json auto-export envelope for the downstream pipeline.")
    var register: Bool = false

    @Option(help: "Export folder for --register (overrides the folder configured in Lorre settings).")
    var exportDir: String?

    @Option(help: "ASR language code (e.g. nl, en). Omit for automatic detection.")
    var language: String?

    @Flag(inversion: .prefixedNo, help: "Enable/disable speaker diarization. Defaults to the Lorre setting.")
    var diarization: Bool?

    @Option(help: "Expected speaker count hint.")
    var speakers: Int?

    @Flag(help: "Suppress progress output on stderr.")
    var quiet: Bool = false

    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: inputURL.path(percentEncoded: false)) else {
            throw ValidationError("Input file not found: \(input)")
        }
        let outputPlan = try TranscribeOutputPlan.resolve(format: format, out: out)

        let factory = TranscribeServiceFactory()
        let settings = try await factory.settings.load()

        let store: FileSessionStore
        var tempBase: URL?
        if register {
            store = FileSessionStore()
        } else {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("lorre-cli-\(UUID().uuidString)", isDirectory: true)
            tempBase = base
            store = FileSessionStore(baseURL: base)
        }
        defer { if let tempBase { try? FileManager.default.removeItem(at: tempBase) } }

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
        let enableDiarization = diarization ?? settings.isSpeakerDiarizationEnabled
        let speakerHint: DiarizationSpeakerCountHint = speakers.map { .exact($0) } ?? settings.diarizationExpectedSpeakerCountHint
        let languageCode = language ?? settings.batchTranscriptionLanguage.languageCode

        let transcript = try await coordinator.process(
            sessionId: session.id,
            enableDiarization: enableDiarization,
            diarizationExpectedSpeakers: speakerHint,
            exportDiarizationDebugArtifact: false,
            deleteAudioAfterTranscription: false,
            languageCode: languageCode,
            onProgress: { [quiet] update in
                guard !quiet else { return }
                FileHandle.standardError.write(Data("[\(Int((update.fraction ?? 0) * 100))%] \(update.label)\n".utf8))
            }
        )

        let reloaded = (try? await store.loadSession(id: session.id)) ?? session
        let renderer = MarkdownExportService()

        try emit(plan: outputPlan, session: reloaded, transcript: transcript, renderer: renderer)

        if register {
            let configuration = registerExportConfiguration(settings: settings)
            guard configuration.folderURL != nil else {
                throw ValidationError("--register needs an export folder. Set one in Lorre settings or pass --export-dir <path>.")
            }
            let result = try await AutomaticExporter.writeEnvelope(
                session: reloaded, transcript: transcript, configuration: configuration, exporter: renderer
            )
            if !quiet {
                FileHandle.standardError.write(Data("Registered session \(reloaded.id) → \(result.json.lastPathComponent)\n".utf8))
            }
        }
    }

    private func registerExportConfiguration(settings: AppSettings) -> AutomaticMarkdownExportConfiguration {
        guard let exportDir else { return settings.automaticMarkdownExport }
        return AutomaticMarkdownExportConfiguration(
            isEnabled: true,
            folderPath: exportDir,
            fileNameTemplate: settings.automaticMarkdownExport.fileNameTemplate
        )
    }

    private func emit(
        plan: TranscribeOutputPlan,
        session: SessionManifest,
        transcript: TranscriptDocument,
        renderer: MarkdownExportService
    ) throws {
        switch plan {
        case .stdout(.markdown):
            print(renderer.render(session: session, transcript: transcript))
        case .stdout(.json):
            FileHandle.standardOutput.write(try renderer.renderJSON(session: session, transcript: transcript))
        case .stdout(.plainText):
            print(renderer.renderPlainText(session: session, transcript: transcript))
        case let .file(url, .markdown):
            try Data(renderer.render(session: session, transcript: transcript).utf8).write(to: url)
        case let .file(url, .plainText):
            try Data(renderer.renderPlainText(session: session, transcript: transcript).utf8).write(to: url)
        case let .file(url, .json):
            try renderer.renderJSON(session: session, transcript: transcript).write(to: url)
        case let .pair(markdownURL, jsonURL):
            try Data(renderer.render(session: session, transcript: transcript).utf8).write(to: markdownURL)
            try renderer.renderJSON(session: session, transcript: transcript).write(to: jsonURL)
        }
    }
}
