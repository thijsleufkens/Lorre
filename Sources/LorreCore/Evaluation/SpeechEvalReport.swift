import Foundation

/// The outcome for one manifest item. Flat and Codable so `--json` runs can be compared.
public struct SpeechEvalItemResult: Codable, Equatable, Sendable {
    public var id: String
    /// Set when the item could not run; the numbers are then absent.
    public var error: String?
    /// Reported problems that did not stop the item (a reference file that could not be read).
    public var notes: [String]
    public var durationSeconds: Double?
    public var processingSeconds: Double?
    public var realTimeFactor: Double?
    public var wer: Double?
    public var substitutions: Int?
    public var deletions: Int?
    public var insertions: Int?
    public var referenceWords: Int?
    public var speakersFound: Int?
    public var speakersExpected: Int?
    public var speakerAccuracy: Double?
    public var speakerScoredMs: Int?

    public init(
        id: String, error: String? = nil, notes: [String] = [], durationSeconds: Double? = nil,
        processingSeconds: Double? = nil, wer: WordErrorRate? = nil, speaker: SpeakerScore? = nil
    ) {
        self.id = id
        self.error = error
        self.notes = notes
        self.durationSeconds = durationSeconds
        self.processingSeconds = processingSeconds
        if let durationSeconds, let processingSeconds, durationSeconds > 0 {
            self.realTimeFactor = processingSeconds / durationSeconds
        }
        self.wer = wer?.rate
        self.substitutions = wer?.substitutions
        self.deletions = wer?.deletions
        self.insertions = wer?.insertions
        self.referenceWords = wer?.referenceWords
        self.speakersFound = speaker?.hypothesisSpeakers
        self.speakersExpected = speaker?.referenceSpeakers
        self.speakerAccuracy = speaker?.accuracy
        self.speakerScoredMs = speaker?.scoredMs
    }

    var werCounts: WordErrorRate? {
        guard let substitutions, let deletions, let insertions, let referenceWords else { return nil }
        return WordErrorRate(substitutions: substitutions, deletions: deletions, insertions: insertions, referenceWords: referenceWords)
    }
}

public struct SpeechEvalTotals: Codable, Equatable, Sendable {
    public var items: Int
    public var failedItems: Int
    /// Word error rate over all reference words pooled; nil when no item had a reference text.
    public var wer: Double?
    public var referenceWords: Int
    /// Mean speaker accuracy weighted by scored time; nil when no item had reference turns.
    public var speakerAccuracy: Double?
    public var speakerScoredMs: Int
    public var durationSeconds: Double
    public var processingSeconds: Double
    public var realTimeFactor: Double?

    public init(results: [SpeechEvalItemResult]) {
        items = results.count
        failedItems = results.filter { $0.error != nil }.count
        let werItems = results.compactMap(\.werCounts)
        let pooled = WordErrorRate.pooled(werItems)
        referenceWords = pooled.referenceWords
        wer = werItems.isEmpty ? nil : pooled.rate
        var weightedCorrect = 0.0
        var scored = 0
        for result in results {
            guard let accuracy = result.speakerAccuracy, let ms = result.speakerScoredMs else { continue }
            weightedCorrect += accuracy * Double(ms)
            scored += ms
        }
        speakerScoredMs = scored
        speakerAccuracy = scored > 0 ? weightedCorrect / Double(scored) : nil
        let ran = results.filter { $0.error == nil }
        durationSeconds = ran.compactMap(\.durationSeconds).reduce(0, +)
        processingSeconds = ran.compactMap(\.processingSeconds).reduce(0, +)
        realTimeFactor = durationSeconds > 0 ? processingSeconds / durationSeconds : nil
    }
}

/// What a run says about itself, so two runs can be compared.
public struct SpeechEvalRun: Codable, Equatable, Sendable {
    public var manifest: String
    public var license: String?
    public var speechEngine: String
    public var speakerEngine: String
    public var diarization: Bool

    public init(manifest: String, license: String?, speechEngine: String, speakerEngine: String, diarization: Bool) {
        self.manifest = manifest
        self.license = license
        self.speechEngine = speechEngine
        self.speakerEngine = speakerEngine
        self.diarization = diarization
    }
}

public struct SpeechEvalReport: Codable, Equatable, Sendable {
    public var run: SpeechEvalRun
    public var items: [SpeechEvalItemResult]
    public var totals: SpeechEvalTotals

    public init(run: SpeechEvalRun, items: [SpeechEvalItemResult]) {
        self.run = run
        self.items = items
        self.totals = SpeechEvalTotals(results: items)
    }
}
