import Foundation
import XCTest
@testable import Lorre

final class AutomaticExportFileNameBuilderTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_716_900_000) // 2024-05-28 12:40:00 UTC-ish

    func testPreviewSubstitutesDateAndTimeTokens() {
        let preview = AutomaticExportFileNameBuilder.previewFileName(
            template: "{date}-{time}.md",
            now: referenceDate
        )
        // Tokens must be replaced (no literal braces left) and a .md extension kept.
        XCTAssertFalse(preview.contains("{"))
        XCTAssertFalse(preview.contains("}"))
        XCTAssertTrue(preview.hasSuffix(".md"))
    }

    func testPreviewFallsBackToDefaultForEmptyTemplate() {
        let preview = AutomaticExportFileNameBuilder.previewFileName(template: "   ", now: referenceDate)
        XCTAssertFalse(preview.isEmpty)
        XCTAssertTrue(preview.hasSuffix(".md"))
    }

    func testFileNameSanitizesUnsafeCharacters() {
        let session = SessionManifest(
            id: UUID(),
            title: "Q3 / Plan: review",
            status: .ready,
            createdAt: referenceDate,
            recordingSource: .microphone,
            audioFileName: "audio.caf"
        )
        let transcript = TranscriptDocument(
            sessionId: session.id,
            sourceEngine: "test",
            segments: [],
            speakers: []
        )
        let name = AutomaticExportFileNameBuilder.fileName(
            session: session,
            transcript: transcript,
            template: "{date}-{smart_title}.md",
            now: referenceDate
        )
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertTrue(name.hasSuffix(".md"))
    }
}
