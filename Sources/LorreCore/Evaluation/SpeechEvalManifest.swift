import Foundation

/// Parses RTTM: `SPEAKER <file> 1 <start> <duration> <NA> <NA> <name> <NA> <NA>`, seconds as decimals.
/// Other line types (`SPKR-INFO`, `LEXEME`, ...), comments, blank lines and malformed lines are ignored.
public enum RTTM {
    public static func parse(_ text: String) -> [SpeakerTurn] {
        var turns: [SpeakerTurn] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 8, fields[0] == "SPEAKER",
                  let start = Double(fields[3]), let duration = Double(fields[4]),
                  start.isFinite, duration.isFinite, start >= 0, duration > 0
            else { continue }
            let startMs = Int((start * 1000).rounded())
            let endMs = Int(((start + duration) * 1000).rounded())
            guard endMs > startMs else { continue }
            turns.append(SpeakerTurn(speaker: String(fields[7]), startMs: startMs, endMs: endMs))
        }
        return turns
    }
}

/// A JSON file next to the audio that lists recordings with their known answers. See `docs/eval-speech.md`.
public struct SpeechEvalManifest: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public var id: String
        /// Path relative to the manifest.
        public var audio: String
        /// Optional second track, for the per-track path.
        public var microphoneAudio: String?
        public var language: String?
        public var referenceText: String?
        /// Plain text file relative to the manifest.
        public var referenceTextFile: String?
        public var referenceTurns: [SpeakerTurn]?
        /// RTTM file relative to the manifest.
        public var referenceRTTM: String?

        public init(
            id: String, audio: String, microphoneAudio: String? = nil, language: String? = nil,
            referenceText: String? = nil, referenceTextFile: String? = nil,
            referenceTurns: [SpeakerTurn]? = nil, referenceRTTM: String? = nil
        ) {
            self.id = id
            self.audio = audio
            self.microphoneAudio = microphoneAudio
            self.language = language
            self.referenceText = referenceText
            self.referenceTextFile = referenceTextFile
            self.referenceTurns = referenceTurns
            self.referenceRTTM = referenceRTTM
        }
    }

    public var name: String
    public var license: String?
    public var items: [Item]

    public init(name: String, license: String? = nil, items: [Item]) {
        self.name = name
        self.license = license
        self.items = items
    }

    public static func load(from data: Data) throws -> SpeechEvalManifest {
        try JSONDecoder().decode(SpeechEvalManifest.self, from: data)
    }
}

/// What an item resolves to on disk: the audio location and whatever reference could be read.
public struct ResolvedSpeechItem: Sendable {
    public var id: String
    public var audioURL: URL
    public var language: String?
    public var referenceText: String?
    public var referenceTurns: [SpeakerTurn]?
    /// Problems that make the item unusable or only partly scoreable; reported per item.
    public var problems: [String]
    /// True when the audio file is missing, so the item cannot run.
    public var audioMissing: Bool

    public init(
        id: String, audioURL: URL, language: String?, referenceText: String?,
        referenceTurns: [SpeakerTurn]?, problems: [String], audioMissing: Bool
    ) {
        self.id = id
        self.audioURL = audioURL
        self.language = language
        self.referenceText = referenceText
        self.referenceTurns = referenceTurns
        self.problems = problems
        self.audioMissing = audioMissing
    }
}

public extension SpeechEvalManifest.Item {
    /// Resolves paths against the manifest's folder and reads the reference files.
    /// A missing reference file is a problem for that item only.
    func resolve(baseDirectory: URL, fileManager: FileManager = .default) -> ResolvedSpeechItem {
        func url(_ relative: String) -> URL {
            if relative.hasPrefix("/") { return URL(fileURLWithPath: relative) }
            return baseDirectory.appendingPathComponent(relative)
        }
        var problems: [String] = []
        let audioURL = url(audio)
        let audioMissing = !fileManager.fileExists(atPath: audioURL.path(percentEncoded: false))
        if audioMissing { problems.append("audio file not found: \(audio)") }
        if let microphoneAudio, !fileManager.fileExists(atPath: url(microphoneAudio).path(percentEncoded: false)) {
            problems.append("microphone audio file not found: \(microphoneAudio)")
        }

        var text = referenceText
        if text == nil, let referenceTextFile {
            if let data = try? Data(contentsOf: url(referenceTextFile)) {
                text = String(decoding: data, as: UTF8.self)
            } else {
                problems.append("reference text file not found: \(referenceTextFile)")
            }
        }
        var turns = referenceTurns
        if turns == nil, let referenceRTTM {
            if let data = try? Data(contentsOf: url(referenceRTTM)) {
                let parsed = RTTM.parse(String(decoding: data, as: UTF8.self))
                if parsed.isEmpty {
                    problems.append("reference RTTM has no SPEAKER lines: \(referenceRTTM)")
                } else {
                    turns = parsed
                }
            } else {
                problems.append("reference RTTM file not found: \(referenceRTTM)")
            }
        }
        return ResolvedSpeechItem(
            id: id, audioURL: audioURL, language: language, referenceText: text, referenceTurns: turns,
            problems: problems, audioMissing: audioMissing
        )
    }
}
