import Foundation
import XCTest
@testable import Lorre

final class AutomaticExporterTests: XCTestCase {
    private func decodeFixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    func testWritesMarkdownAndJSONEnvelope() async throws {
        let session = try decodeFixture(SessionManifest.self, "session-manifest-v1-with-version.json")
        let transcript = try decodeFixture(TranscriptDocument.self, "transcript-document-v1.json")
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ae-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = AutomaticMarkdownExportConfiguration(
            isEnabled: true,
            folderPath: folder.path(percentEncoded: false),
            fileNameTemplate: AutomaticMarkdownExportConfiguration.defaultFileNameTemplate
        )

        let result = try await AutomaticExporter.writeEnvelope(
            session: session,
            transcript: transcript,
            configuration: config,
            exporter: MarkdownExportService()
        )

        XCTAssertEqual(result.markdown.pathExtension, "md")
        XCTAssertEqual(result.json.pathExtension, "json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.markdown.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.json.path(percentEncoded: false)))

        let data = try Data(contentsOf: result.json)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["session"])
        XCTAssertNotNil(object?["transcript"])
        XCTAssertNotNil(object?["exportedAt"])
    }

    func testCollidingFileNamesFromDifferentSessionsDoNotOverwrite() async throws {
        let sessionA = try decodeFixture(SessionManifest.self, "session-manifest-v1-with-version.json")
        var sessionB = sessionA
        sessionB.id = UUID()

        var transcriptA = try decodeFixture(TranscriptDocument.self, "transcript-document-v1.json")
        transcriptA.sessionId = sessionA.id
        var transcriptB = transcriptA
        transcriptB.sessionId = sessionB.id

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ae-collision-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Same title + same template ⇒ both sessions render the same file name.
        let config = AutomaticMarkdownExportConfiguration(
            isEnabled: true,
            folderPath: folder.path(percentEncoded: false),
            fileNameTemplate: "{session_title}"
        )

        let resultA = try await AutomaticExporter.writeEnvelope(
            session: sessionA, transcript: transcriptA, configuration: config, exporter: MarkdownExportService()
        )
        let resultB = try await AutomaticExporter.writeEnvelope(
            session: sessionB, transcript: transcriptB, configuration: config, exporter: MarkdownExportService()
        )

        XCTAssertNotEqual(resultA.json, resultB.json, "A second session must not claim the first session's envelope path")

        func envelopeSessionID(at url: URL) throws -> String? {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            return (object?["session"] as? [String: Any])?["id"] as? String
        }
        XCTAssertEqual(try envelopeSessionID(at: resultA.json), sessionA.id.uuidString)
        XCTAssertEqual(try envelopeSessionID(at: resultB.json), sessionB.id.uuidString)

        // Re-exporting the same session must keep updating its own files.
        let resultA2 = try await AutomaticExporter.writeEnvelope(
            session: sessionA, transcript: transcriptA, configuration: config, exporter: MarkdownExportService()
        )
        XCTAssertEqual(resultA2.json, resultA.json)
    }

    func testThrowsWhenNoFolderConfigured() async throws {
        let session = try decodeFixture(SessionManifest.self, "session-manifest-v1-with-version.json")
        let transcript = try decodeFixture(TranscriptDocument.self, "transcript-document-v1.json")
        let config = AutomaticMarkdownExportConfiguration(isEnabled: false, folderPath: nil)
        do {
            _ = try await AutomaticExporter.writeEnvelope(
                session: session, transcript: transcript, configuration: config, exporter: MarkdownExportService()
            )
            XCTFail("expected noFolder")
        } catch let error as AutomaticExporter.ExportError {
            XCTAssertEqual(error, .noFolder)
        }
    }
}
