import XCTest
@testable import Lorre

final class BatchTranscriptionLanguageTests: XCTestCase {
    func testAutomaticHasNoLanguageCode() {
        XCTAssertNil(BatchTranscriptionLanguage.automatic.languageCode)
    }

    func testConcreteLanguageCodeMatchesRawValue() {
        for language in BatchTranscriptionLanguage.allCases where language != .automatic {
            XCTAssertEqual(language.languageCode, language.rawValue)
        }
        XCTAssertEqual(BatchTranscriptionLanguage.dutch.languageCode, "nl")
        XCTAssertEqual(BatchTranscriptionLanguage.german.languageCode, "de")
    }

    func testTranscriptDocumentDefaultLanguageHintIsNil() {
        let doc = TranscriptDocument(sessionId: UUID(), sourceEngine: "test", segments: [], speakers: [])
        XCTAssertNil(doc.languageHint)
    }
}
