import XCTest
@testable import Lorre

final class BatchTranscriptionLanguageTests: XCTestCase {
    func testAutomaticHasNoLanguageCode() {
        XCTAssertNil(BatchTranscriptionLanguage.automatic.languageCode)
    }

    func testConcreteLanguageCodeMatchesRawValue() {
        XCTAssertEqual(BatchTranscriptionLanguage.dutch.languageCode, "nl")
        XCTAssertEqual(BatchTranscriptionLanguage.english.languageCode, "en")
    }
}
