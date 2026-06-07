import XCTest
@testable import Lorre

final class TranscriptAssemblerLanguageTests: XCTestCase {
    private func sampleTranscription() -> TranscriptionResult {
        TranscriptionResult(
            engineName: "test",
            utterances: [
                TranscriptionUtterance(startMs: 0, endMs: 1000, text: "Hallo", confidence: nil)
            ]
        )
    }

    func testStampsProvidedLanguageHint() {
        let doc = TranscriptAssembler.assemble(
            sessionId: UUID(),
            transcription: sampleTranscription(),
            diarization: nil,
            languageHint: "nl"
        )
        XCTAssertEqual(doc.languageHint, "nl")
    }

    func testNilLanguageHintWhenOmitted() {
        let doc = TranscriptAssembler.assemble(
            sessionId: UUID(),
            transcription: sampleTranscription(),
            diarization: nil
        )
        XCTAssertNil(doc.languageHint)
    }
}
