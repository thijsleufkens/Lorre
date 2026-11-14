import ArgumentParser
import AVFoundation
import Foundation
import LorreCore

/// Runs the headless speech pipeline over recordings with known answers and reports word error
/// rate and speaker separation. Writes nothing outside a temporary folder it removes afterwards.
struct EvalSpeechCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eval-speech",
        abstract: "Measure speech recognition and speaker separation on recordings with known answers. Writes nothing."
    )

    @Argument(help: "Path of the manifest JSON file (format: docs/eval-speech.md).")
    var manifest: String

    @Option(help: "Run only the first N items.")
    var limit: Int?

    @Flag(help: "Print JSON instead of text.")
    var json: Bool = false

    @Flag(help: "Skip speaker separation: only the text is measured.")
    var noDiarization: Bool = false

    @Flag(help: "Suppress progress output on stderr.")
    var quiet: Bool = false

    func run() async throws {
        let manifestURL = URL(fileURLWithPath: (manifest as NSString).expandingTildeInPath)
        let parsed: SpeechEvalManifest
        do {
            parsed = try SpeechEvalManifest.load(from: try Data(contentsOf: manifestURL))
        } catch {
            throw ValidationError("Cannot read the manifest \(manifest): \(error.localizedDescription)")
        }
        if let limit, limit < 1 { throw ValidationError("--limit must be at least 1.") }
        let items = limit.map { Array(parsed.items.prefix($0)) } ?? parsed.items
        guard !items.isEmpty else { throw ValidationError("The manifest has no items.") }

        let factory = TranscribeServiceFactory()
        let settings = try await factory.settings.load()
        await factory.diarization.setDiarizationEngine(settings.diarizationEngine)
        var speechEngine = "unknown"
        let speakerEngine = noDiarization ? "none" : settings.diarizationEngine.rawValue

        var results: [SpeechEvalItemResult] = []
        for item in items {
            let resolved = item.resolve(baseDirectory: manifestURL.deletingLastPathComponent())
            if !quiet { FileHandle.standardError.write(Data("[\(item.id)] running\n".utf8)) }
            if resolved.audioMissing {
                results.append(SpeechEvalItemResult(id: item.id, error: resolved.problems.joined(separator: "; ")))
                continue
            }
            do {
                let outcome = try await Self.runPipeline(
                    audio: resolved.audioURL, factory: factory,
                    language: resolved.language ?? settings.batchTranscriptionLanguage.languageCode,
                    diarization: !noDiarization
                )
                speechEngine = outcome.speechEngine
                results.append(Self.score(resolved, outcome: outcome, diarization: !noDiarization))
            } catch {
                results.append(SpeechEvalItemResult(
                    id: item.id, error: error.localizedDescription
                ))
            }
        }

        let report = SpeechEvalReport(
            run: SpeechEvalRun(
                manifest: parsed.name, license: parsed.license, speechEngine: speechEngine,
                speakerEngine: speakerEngine, diarization: !noDiarization
            ),
            items: results
        )
        print(try Self.render(report, json: json))
    }

    // MARK: Pipeline

    struct PipelineOutcome {
        var text: String
        var speechEngine: String
        var turns: [SpeakerTurn]
        var durationSeconds: Double
        var processingSeconds: Double
    }

    /// The same flow as `transcribe` without `--register`: a throwaway session store in a temp folder.
    static func runPipeline(
        audio: URL, factory: TranscribeServiceFactory, language: String?, diarization: Bool
    ) async throws -> PipelineOutcome {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("lorre-eval-speech-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = FileSessionStore(baseURL: base)
        let coordinator = ProcessingCoordinator(
            store: store, transcriptionService: factory.transcription, diarizationService: factory.diarization
        )
        var session = try await store.createSession(NewSessionDraft(
            title: audio.deletingPathExtension().lastPathComponent, folderId: nil, status: .processing,
            durationSeconds: nil, recordingSource: .microphone, audioFileName: "audio.m4a",
            microphoneStemFileName: nil, systemAudioStemFileName: nil, recordedAt: Date()
        ))
        let directory = await store.sessionDirectoryURL(for: session.id)
        let audioFileName = try await MediaAudioImporter.prepareAudio(from: audio, intoDirectory: directory)
        if audioFileName != session.audioFileName {
            session.audioFileName = audioFileName
            session.updatedAt = Date()
            try await store.updateSession(session)
        }
        var duration = 0.0
        if let file = try? AVAudioFile(forReading: directory.appendingPathComponent(audioFileName)),
           file.processingFormat.sampleRate > 0 {
            duration = Double(file.length) / file.processingFormat.sampleRate
        }

        let started = Date()
        let transcript = try await coordinator.process(
            sessionId: session.id,
            enableDiarization: diarization,
            diarizationExpectedSpeakers: .auto,
            exportDiarizationDebugArtifact: false,
            deleteAudioAfterTranscription: false,
            languageCode: language,
            onProgress: { _ in }
        )
        let processing = Date().timeIntervalSince(started)
        if duration == 0 { duration = Double(transcript.segments.map(\.endMs).max() ?? 0) / 1000 }

        let turns = transcript.segments.compactMap { segment -> SpeakerTurn? in
            guard let speaker = segment.speakerId, segment.endMs > segment.startMs else { return nil }
            return SpeakerTurn(speaker: speaker, startMs: segment.startMs, endMs: segment.endMs)
        }
        return PipelineOutcome(
            text: transcript.segments.map(\.text).joined(separator: " "), speechEngine: transcript.sourceEngine,
            turns: turns, durationSeconds: duration, processingSeconds: processing
        )
    }

    /// Turns one pipeline outcome into numbers, as far as the item has references.
    static func score(_ item: ResolvedSpeechItem, outcome: PipelineOutcome, diarization: Bool) -> SpeechEvalItemResult {
        var wer: WordErrorRate?
        if let referenceText = item.referenceText {
            wer = WordErrorRate.compute(
                reference: TextNormalizer.words(referenceText),
                hypothesis: TextNormalizer.words(outcome.text)
            )
        }
        var speaker: SpeakerScore?
        if diarization, let turns = item.referenceTurns {
            speaker = SpeakerScore.compute(reference: turns, hypothesis: outcome.turns)
        }
        return SpeechEvalItemResult(
            id: item.id, notes: item.problems, durationSeconds: outcome.durationSeconds,
            processingSeconds: outcome.processingSeconds, wer: wer, speaker: speaker
        )
    }

    // MARK: Rendering

    static func render(_ report: SpeechEvalReport, json: Bool) throws -> String {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return String(decoding: try encoder.encode(report), as: UTF8.self)
        }
        var lines = [
            "Manifest: \(report.run.manifest)" + (report.run.license.map { " (license: \($0))" } ?? ""),
            "Speech engine: \(report.run.speechEngine)",
            "Speaker engine: \(report.run.speakerEngine)",
            "",
            pad("id", 24) + pad("audio", 9) + pad("proc", 9) + pad("RTF", 7) + pad("WER", 8) + pad("speakers", 10) + "speaker acc.",
        ]
        for item in report.items {
            if let error = item.error {
                lines.append(pad(item.id, 24) + "FAILED: \(error)")
                continue
            }
            let speakers = item.speakersFound.map { found in
                "\(found)/\(item.speakersExpected.map(String.init) ?? "?")"
            } ?? "-"
            lines.append(
                pad(item.id, 24) + pad(seconds(item.durationSeconds), 9) + pad(seconds(item.processingSeconds), 9)
                    + pad(item.realTimeFactor.map { String(format: "%.2f", $0) } ?? "-", 7)
                    + pad(item.wer.map(percent) ?? "-", 8) + pad(speakers, 10)
                    + (item.speakerAccuracy.map(percent) ?? "-")
            )
            for note in item.notes { lines.append("    note: \(note)") }
        }
        let totals = report.totals
        lines.append("")
        lines.append("Items: \(totals.items), failed: \(totals.failedItems)")
        lines.append("WER (pooled over \(totals.referenceWords) reference words): \(totals.wer.map(percent) ?? "-")")
        lines.append("Speaker accuracy (weighted by scored time, \(String(format: "%.0f", Double(totals.speakerScoredMs) / 1000)) s): \(totals.speakerAccuracy.map(percent) ?? "-")")
        lines.append("Audio \(seconds(totals.durationSeconds)), processing \(seconds(totals.processingSeconds)), real-time factor \(totals.realTimeFactor.map { String(format: "%.2f", $0) } ?? "-")")
        return lines.joined(separator: "\n")
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    private static func seconds(_ value: Double?) -> String {
        value.map { String(format: "%.1fs", $0) } ?? "-"
    }

    private static func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
}
