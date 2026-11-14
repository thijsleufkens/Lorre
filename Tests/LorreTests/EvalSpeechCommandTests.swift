import ArgumentParser
import XCTest
import LorreCore
@testable import Lorre

final class EvalSpeechCommandTests: XCTestCase {
    func testIsRegisteredAndRouted() {
        let registered = Set(LorreCLI.configuration.subcommands.compactMap { $0.configuration.commandName })
        XCTAssertTrue(registered.contains("eval-speech"))
        XCTAssertTrue(CLIRouting.subcommands.contains("eval-speech"))
        XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", "eval-speech"]))
    }

    func testParsesItsOptions() throws {
        let command = try EvalSpeechCommand.parse(["m.json", "--limit", "3", "--json", "--no-diarization"])
        XCTAssertEqual(command.manifest, "m.json")
        XCTAssertEqual(command.limit, 3)
        XCTAssertTrue(command.json)
        XCTAssertTrue(command.noDiarization)
        let defaults = try EvalSpeechCommand.parse(["m.json"])
        XCTAssertNil(defaults.limit)
        XCTAssertFalse(defaults.json)
        XCTAssertFalse(defaults.noDiarization)
    }

    private func canned() -> SpeechEvalReport {
        let first = SpeechEvalItemResult(
            id: "meeting-1", durationSeconds: 100, processingSeconds: 10,
            wer: WordErrorRate(substitutions: 5, deletions: 3, insertions: 2, referenceWords: 100),
            speaker: SpeakerScore(
                referenceSpeakers: 2, hypothesisSpeakers: 3, scoredMs: 60_000,
                correctMs: 54_000, missedMs: 3_000, confusedMs: 3_000, accuracy: 0.9
            )
        )
        let second = SpeechEvalItemResult(
            id: "meeting-2", durationSeconds: 300, processingSeconds: 15,
            wer: WordErrorRate(substitutions: 10, deletions: 10, insertions: 10, referenceWords: 300),
            speaker: SpeakerScore(
                referenceSpeakers: 4, hypothesisSpeakers: 4, scoredMs: 180_000,
                correctMs: 90_000, missedMs: 0, confusedMs: 90_000, accuracy: 0.5
            )
        )
        let failed = SpeechEvalItemResult(id: "gone", error: "audio file not found: gone.wav")
        return SpeechEvalReport(
            run: SpeechEvalRun(manifest: "mini", license: "CC BY 4.0", speechEngine: "ASR-X", speakerEngine: "offlineVbx", diarization: true),
            items: [first, second, failed]
        )
    }

    func testTotalsPoolWordsAndWeightSpeakerAccuracyByScoredTime() throws {
        let totals = canned().totals
        XCTAssertEqual(totals.items, 3)
        XCTAssertEqual(totals.failedItems, 1)
        XCTAssertEqual(totals.referenceWords, 400)
        XCTAssertEqual(try XCTUnwrap(totals.wer), 40.0 / 400.0, accuracy: 1e-9)
        // (0.9 * 60 + 0.5 * 180) / 240 = 0.6
        XCTAssertEqual(try XCTUnwrap(totals.speakerAccuracy), 0.6, accuracy: 1e-9)
        XCTAssertEqual(totals.durationSeconds, 400)
        XCTAssertEqual(totals.processingSeconds, 25)
        XCTAssertEqual(try XCTUnwrap(totals.realTimeFactor), 25.0 / 400.0, accuracy: 1e-9)
    }

    func testTotalsAreNilWithoutReferences() {
        let totals = SpeechEvalTotals(results: [SpeechEvalItemResult(id: "x", durationSeconds: 10, processingSeconds: 1)])
        XCTAssertNil(totals.wer)
        XCTAssertNil(totals.speakerAccuracy)
    }

    func testTextRendering() throws {
        let text = try EvalSpeechCommand.render(canned(), json: false)
        XCTAssertTrue(text.contains("Speech engine: ASR-X"))
        XCTAssertTrue(text.contains("Speaker engine: offlineVbx"))
        let line = try XCTUnwrap(text.split(separator: "\n").first { $0.hasPrefix("meeting-1") })
        XCTAssertTrue(line.contains("100.0s"))
        XCTAssertTrue(line.contains("0.10"))
        XCTAssertTrue(line.contains("10.0%"))
        XCTAssertTrue(line.contains("3/2"))
        XCTAssertTrue(line.contains("90.0%"))
        XCTAssertTrue(text.contains("FAILED: audio file not found: gone.wav"))
        XCTAssertTrue(text.contains("WER (pooled over 400 reference words): 10.0%"))
        XCTAssertTrue(text.contains(": 60.0%"))
    }

    func testJSONRenderingCarriesEnginesAndRoundTrips() throws {
        let output = try EvalSpeechCommand.render(canned(), json: true)
        let decoded = try JSONDecoder().decode(SpeechEvalReport.self, from: Data(output.utf8))
        XCTAssertEqual(decoded, canned())
        XCTAssertEqual(decoded.run.speechEngine, "ASR-X")
        XCTAssertEqual(decoded.run.speakerEngine, "offlineVbx")
    }

    func testScoreUsesReferencesWhenPresent() throws {
        let item = ResolvedSpeechItem(
            id: "a", audioURL: URL(fileURLWithPath: "/x.wav"), language: nil,
            referenceText: "Hallo wereld, goedemorgen.",
            referenceTurns: [SpeakerTurn(speaker: "anna", startMs: 0, endMs: 3_000)],
            problems: ["note"], audioMissing: false
        )
        let outcome = EvalSpeechCommand.PipelineOutcome(
            text: "hallo wereld goedemiddag", speechEngine: "E",
            turns: [SpeakerTurn(speaker: "S1", startMs: 0, endMs: 3_000)], durationSeconds: 3, processingSeconds: 1
        )
        let result = EvalSpeechCommand.score(item, outcome: outcome, diarization: true)
        XCTAssertEqual(try XCTUnwrap(result.wer), 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(result.speakerAccuracy, 1)
        XCTAssertEqual(result.notes, ["note"])
        let textOnly = EvalSpeechCommand.score(item, outcome: outcome, diarization: false)
        XCTAssertNil(textOnly.speakerAccuracy)
    }
}
