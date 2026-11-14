import XCTest
@testable import LorreCore

final class TextNormalizerTests: XCTestCase {
    func testLowercasesAndStripsPunctuation() {
        XCTAssertEqual(TextNormalizer.words("Hallo, wereld! Hoe gaat het?"), ["hallo", "wereld", "hoe", "gaat", "het"])
    }

    func testDutchApostrophesJoinTheWord() {
        XCTAssertEqual(TextNormalizer.words("Dat is zo'n auto's en m\u{2019}n fiets"), ["dat", "is", "zon", "autos", "en", "mn", "fiets"])
    }

    func testHyphenAndDashesSeparate() {
        XCTAssertEqual(TextNormalizer.words("e-mail \u{2013} nou ja... klaar"), ["e", "mail", "nou", "ja", "klaar"])
    }

    func testDiacriticsKeptByDefaultAndFoldedOnRequest() {
        XCTAssertEqual(TextNormalizer.words("Café Zoë"), ["café", "zoë"])
        XCTAssertEqual(TextNormalizer.words("Café Zoë", foldDiacritics: true), ["cafe", "zoe"])
    }

    func testDigitsStayAndWhitespaceCollapses() {
        XCTAssertEqual(TextNormalizer.words("  3,5   procent\n\t in 2026 "), ["3", "5", "procent", "in", "2026"])
        XCTAssertEqual(TextNormalizer.words(""), [])
        XCTAssertEqual(TextNormalizer.words("?!..."), [])
    }
}

final class WordErrorRateTests: XCTestCase {
    private func wer(_ reference: String, _ hypothesis: String) -> WordErrorRate {
        WordErrorRate.compute(reference: TextNormalizer.words(reference), hypothesis: TextNormalizer.words(hypothesis))
    }

    func testEqual() {
        let result = wer("de kat zit op de mat", "De kat zit op de mat.")
        XCTAssertEqual(result, WordErrorRate(substitutions: 0, deletions: 0, insertions: 0, referenceWords: 6))
        XCTAssertEqual(result.rate, 0)
    }

    func testSubstitution() {
        let result = wer("de kat zit op de mat", "de kat zat op de mat")
        XCTAssertEqual(result.substitutions, 1)
        XCTAssertEqual(result.deletions, 0)
        XCTAssertEqual(result.insertions, 0)
        XCTAssertEqual(result.rate, 1.0 / 6.0, accuracy: 1e-9)
    }

    func testDeletion() {
        let result = wer("de kat zit op de mat", "de kat op de mat")
        XCTAssertEqual(result, WordErrorRate(substitutions: 0, deletions: 1, insertions: 0, referenceWords: 6))
    }

    func testInsertion() {
        let result = wer("de kat zit", "de grote kat zit")
        XCTAssertEqual(result, WordErrorRate(substitutions: 0, deletions: 0, insertions: 1, referenceWords: 3))
        XCTAssertEqual(result.rate, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testEmptyReferenceCountsInsertionsOverOne() {
        let result = wer("", "een twee drie")
        XCTAssertEqual(result.insertions, 3)
        XCTAssertEqual(result.referenceWords, 0)
        XCTAssertEqual(result.rate, 3)
    }

    func testBothEmptyIsZero() {
        XCTAssertEqual(wer("", "").rate, 0)
    }

    func testEmptyHypothesisIsAllDeletions() {
        let result = wer("een twee drie", "")
        XCTAssertEqual(result, WordErrorRate(substitutions: 0, deletions: 3, insertions: 0, referenceWords: 3))
        XCTAssertEqual(result.rate, 1)
    }

    func testMixedErrorsAddUpToTheEditDistance() {
        // "a b c d" -> "a x c d e": one substitution, one insertion.
        let result = wer("a b c d", "a x c d e")
        XCTAssertEqual(result.errors, 2)
        XCTAssertEqual(result.substitutions + result.insertions, 2)
    }

    func testPooledWeighsByWords() {
        let pooled = WordErrorRate.pooled([
            WordErrorRate(substitutions: 1, deletions: 0, insertions: 0, referenceWords: 10),
            WordErrorRate(substitutions: 0, deletions: 3, insertions: 0, referenceWords: 30),
        ])
        XCTAssertEqual(pooled.rate, 4.0 / 40.0, accuracy: 1e-9)
    }

    func testFiveThousandWordsIsFastAndExact() {
        var generator = SystemRandomNumberGenerator()
        let reference = (0..<5_000).map { _ in "w\(Int.random(in: 0..<800, using: &generator))" }
        var hypothesis = reference
        // 100 substitutions at distinct places, 50 deletions from the tail end, 25 insertions.
        for k in 0..<100 { hypothesis[k * 50] = "zz\(k)" }
        hypothesis.removeLast(50)
        for k in 0..<25 { hypothesis.insert("ins\(k)", at: 100 + k * 190) }
        let started = Date()
        let result = WordErrorRate.compute(reference: reference, hypothesis: hypothesis)
        XCTAssertLessThan(Date().timeIntervalSince(started), 20)
        XCTAssertEqual(result.referenceWords, 5_000)
        // The constructed edit script costs 175; an optimal alignment is never worse.
        XCTAssertLessThanOrEqual(result.errors, 175)
        XCTAssertGreaterThan(result.errors, 100)
        XCTAssertEqual(result.referenceWords - result.deletions + result.insertions, hypothesis.count)
    }
}

final class SpeakerScoreTests: XCTestCase {
    private func turn(_ speaker: String, _ start: Int, _ end: Int) -> SpeakerTurn {
        SpeakerTurn(speaker: speaker, startMs: start, endMs: end)
    }

    private let reference: [SpeakerTurn] = [
        SpeakerTurn(speaker: "anna", startMs: 0, endMs: 10_000),
        SpeakerTurn(speaker: "bram", startMs: 10_000, endMs: 20_000),
        SpeakerTurn(speaker: "anna", startMs: 20_000, endMs: 30_000),
    ]

    func testPerfect() {
        let score = SpeakerScore.compute(reference: reference, hypothesis: reference)
        XCTAssertEqual(score.referenceSpeakers, 2)
        XCTAssertEqual(score.hypothesisSpeakers, 2)
        XCTAssertEqual(score.scoredMs, 30_000)
        XCTAssertEqual(score.correctMs, 30_000)
        XCTAssertEqual(score.accuracy, 1)
    }

    func testSwappedLabelsStillPerfectThroughMapping() {
        let hypothesis = reference.map { turn($0.speaker == "anna" ? "S2" : "S1", $0.startMs, $0.endMs) }
        let score = SpeakerScore.compute(reference: reference, hypothesis: hypothesis)
        XCTAssertEqual(score.accuracy, 1)
        XCTAssertEqual(score.confusedMs, 0)
    }

    func testOneSpeakerSplitInTwo() {
        // Anna's last 10 s are given to a third label; the mapping gives only one label to Anna.
        let hypothesis = [turn("S1", 0, 10_000), turn("S2", 10_000, 20_000), turn("S3", 20_000, 30_000)]
        let score = SpeakerScore.compute(reference: reference, hypothesis: hypothesis)
        XCTAssertEqual(score.hypothesisSpeakers, 3)
        XCTAssertEqual(score.correctMs, 20_000)
        XCTAssertEqual(score.confusedMs, 10_000)
        XCTAssertEqual(score.accuracy, 20.0 / 30.0, accuracy: 1e-9)
    }

    func testMissedStretch() {
        let hypothesis = [turn("S1", 0, 10_000), turn("S2", 10_000, 15_000), turn("S1", 20_000, 30_000)]
        let score = SpeakerScore.compute(reference: reference, hypothesis: hypothesis)
        XCTAssertEqual(score.missedMs, 5_000)
        XCTAssertEqual(score.correctMs, 25_000)
        XCTAssertEqual(score.confusedMs, 0)
    }

    func testReferenceOverlapIsExcludedFromScoring() {
        let overlapping = [turn("anna", 0, 10_000), turn("bram", 5_000, 15_000)]
        let score = SpeakerScore.compute(reference: overlapping, hypothesis: overlapping)
        // 0-5 s anna alone, 5-10 s both, 10-15 s bram alone.
        XCTAssertEqual(score.scoredMs, 10_000)
        XCTAssertEqual(score.correctMs, 10_000)
    }

    func testMoreHypothesisThanReferenceSpeakers() {
        let single = [turn("anna", 0, 20_000)]
        let hypothesis = [turn("A", 0, 12_000), turn("B", 12_000, 16_000), turn("C", 16_000, 20_000)]
        let score = SpeakerScore.compute(reference: single, hypothesis: hypothesis)
        XCTAssertEqual(score.referenceSpeakers, 1)
        XCTAssertEqual(score.hypothesisSpeakers, 3)
        XCTAssertEqual(score.correctMs, 12_000)
        XCTAssertEqual(score.confusedMs, 8_000)
    }

    func testNoHypothesisAndNoReference() {
        let none = SpeakerScore.compute(reference: reference, hypothesis: [])
        XCTAssertEqual(none.missedMs, 30_000)
        XCTAssertEqual(none.accuracy, 0)
        let empty = SpeakerScore.compute(reference: [], hypothesis: [])
        XCTAssertEqual(empty.scoredMs, 0)
        XCTAssertEqual(empty.accuracy, 0)
    }
}

final class RTTMTests: XCTestCase {
    func testParsesSpeakerLinesAndIgnoresTheRest() {
        let text = """
        ;; a comment
        SPKR-INFO file1 1 <NA> <NA> <NA> unknown anna <NA> <NA>
        SPEAKER file1 1 0.500 2.250 <NA> <NA> anna <NA> <NA>
        SPEAKER file1 1 3.000 1.000 <NA> <NA> bram <NA> <NA>

        SPEAKER broken line
        SPEAKER file1 1 abc 1.0 <NA> <NA> carl <NA> <NA>
        SPEAKER file1 1 5.0 0 <NA> <NA> zero <NA> <NA>
        LEXEME file1 1 1.0 0.2 word <NA> anna <NA> <NA>
        """
        XCTAssertEqual(RTTM.parse(text), [
            SpeakerTurn(speaker: "anna", startMs: 500, endMs: 2_750),
            SpeakerTurn(speaker: "bram", startMs: 3_000, endMs: 4_000),
        ])
    }

    func testTabSeparatedAndWindowsLineEndings() {
        let text = "SPEAKER\tf\t1\t1.0\t2.0\t<NA>\t<NA>\tS1\t<NA>\t<NA>\r\nSPEAKER f 1 4.0 1.0 <NA> <NA> S2 <NA> <NA>\r\n"
        XCTAssertEqual(RTTM.parse(text).map(\.speaker), ["S1", "S2"])
    }
}

final class SpeechEvalManifestTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("speech-eval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("audio"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDecodesAManifest() throws {
        let json = """
        {"name": "mini", "license": "CC BY 4.0", "items": [
          {"id": "a", "audio": "audio/a.wav", "language": "nl", "referenceText": "hallo wereld",
           "referenceTurns": [{"speaker": "S1", "startMs": 0, "endMs": 1000}]},
          {"id": "b", "audio": "audio/b.wav", "microphoneAudio": "audio/b-mic.wav",
           "referenceTextFile": "b.txt", "referenceRTTM": "b.rttm"}
        ]}
        """
        let manifest = try SpeechEvalManifest.load(from: Data(json.utf8))
        XCTAssertEqual(manifest.name, "mini")
        XCTAssertEqual(manifest.license, "CC BY 4.0")
        XCTAssertEqual(manifest.items.count, 2)
        XCTAssertEqual(manifest.items[0].referenceTurns?.first?.endMs, 1000)
        XCTAssertEqual(manifest.items[1].microphoneAudio, "audio/b-mic.wav")
        XCTAssertNil(manifest.items[1].referenceText)
    }

    func testInvalidManifestThrows() {
        XCTAssertThrowsError(try SpeechEvalManifest.load(from: Data("{\"items\": []}".utf8)))
    }

    func testResolvesRelativePathsAndReadsReferenceFiles() throws {
        try Data().write(to: directory.appendingPathComponent("audio/a.wav"))
        try Data("Hallo wereld".utf8).write(to: directory.appendingPathComponent("a.txt"))
        try Data("SPEAKER a 1 0.0 2.0 <NA> <NA> S1 <NA> <NA>\n".utf8).write(to: directory.appendingPathComponent("a.rttm"))
        let item = SpeechEvalManifest.Item(id: "a", audio: "audio/a.wav", language: "nl", referenceTextFile: "a.txt", referenceRTTM: "a.rttm")
        let resolved = item.resolve(baseDirectory: directory)
        XCTAssertFalse(resolved.audioMissing)
        XCTAssertEqual(resolved.audioURL.lastPathComponent, "a.wav")
        XCTAssertEqual(resolved.referenceText, "Hallo wereld")
        XCTAssertEqual(resolved.referenceTurns, [SpeakerTurn(speaker: "S1", startMs: 0, endMs: 2_000)])
        XCTAssertEqual(resolved.problems, [])
    }

    func testMissingFilesAreReportedNotThrown() {
        let item = SpeechEvalManifest.Item(id: "x", audio: "nope.wav", referenceTextFile: "nope.txt", referenceRTTM: "nope.rttm")
        let resolved = item.resolve(baseDirectory: directory)
        XCTAssertTrue(resolved.audioMissing)
        XCTAssertEqual(resolved.problems.count, 3)
        XCTAssertNil(resolved.referenceText)
        XCTAssertNil(resolved.referenceTurns)
    }

    func testInlineReferenceWinsOverFile() throws {
        let item = SpeechEvalManifest.Item(id: "a", audio: "a.wav", referenceText: "inline", referenceTextFile: "other.txt")
        XCTAssertEqual(item.resolve(baseDirectory: directory).referenceText, "inline")
    }
}
