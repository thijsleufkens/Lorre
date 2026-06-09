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
