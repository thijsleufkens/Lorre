import Foundation
import XCTest
@testable import Lorre

final class GlobalDictationTextFormatterTests: XCTestCase {
    func testJoinsUtterancesAndNormalizesWhitespace() {
        let result = TranscriptionResult(
            engineName: "test",
            utterances: [
                TranscriptionUtterance(startMs: 0, endMs: 1000, text: "  Hello   there  ", confidence: nil),
                TranscriptionUtterance(startMs: 1000, endMs: 2000, text: "\nworld\t", confidence: nil)
            ]
        )
        let text = GlobalDictationTextFormatter.insertionText(from: result)
        XCTAssertEqual(text, "Hello there world")
    }

    func testEmptyUtterancesProduceEmptyString() {
        let result = TranscriptionResult(engineName: "test", utterances: [])
        XCTAssertEqual(GlobalDictationTextFormatter.insertionText(from: result), "")
    }
}
