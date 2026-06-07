import XCTest
@testable import Lorre

final class JSONExportEnvelopeTests: XCTestCase {
    private struct Envelope: Decodable {
        let session: SessionManifest
        let transcript: TranscriptDocument
        let exportedAt: Date
    }

    func testEnvelopeCarriesSessionIdAndSegments() throws {
        let id = UUID()
        let session = SessionManifest(
            id: id,
            title: "Klantgesprek",
            status: .ready,
            recordingSource: .microphone,
            audioFileName: "audio.caf"
        )
        let transcript = TranscriptDocument(
            sessionId: id,
            languageHint: "nl",
            sourceEngine: "test",
            segments: [
                TranscriptSegment(startMs: 0, endMs: 1000, text: "Hallo", speakerId: "S1", confidence: nil)
            ],
            speakers: [SpeakerProfile.defaultProfile(id: "S1")]
        )

        let data = try MarkdownExportService().renderJSON(session: session, transcript: transcript)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: data)

        XCTAssertEqual(envelope.session.id, id)
        XCTAssertEqual(envelope.transcript.languageHint, "nl")
        XCTAssertEqual(envelope.transcript.segments.count, 1)
        XCTAssertEqual(envelope.transcript.segments.first?.text, "Hallo")
    }
}
