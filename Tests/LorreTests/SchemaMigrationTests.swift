import Foundation
import XCTest
@testable import Lorre

/// Fixture-based migration tests for persisted model schemas.
///
/// Every persisted Codable type in Lorre (`SessionManifest`,
/// `TranscriptDocument`, `AppSettings`) must remain readable from older
/// shapes on disk after a code upgrade. These tests load committed
/// fixtures from `Tests/LorreTests/Fixtures/` via `Bundle.module` and
/// assert that decoding produces sensible defaults for missing fields.
///
/// When adding a non-additive change to any of these schemas, bump the
/// type's `schemaVersion`, add a new fixture for the previous version,
/// and add a test here that exercises the migration path.
final class SchemaMigrationTests: XCTestCase {
    func testSessionManifestDecodesPreVersionFixtureAsV1() throws {
        let manifest = try decodeFixture(SessionManifest.self, named: "session-manifest-v1-pre-version")

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.id, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertEqual(manifest.title, "Pre-version Session")
        XCTAssertEqual(manifest.status, .ready)
        XCTAssertEqual(manifest.recordingSource, .microphone)
        XCTAssertEqual(manifest.audioFileName, "audio.caf")
        XCTAssertEqual(manifest.durationSeconds, 1800)
        XCTAssertNil(manifest.audioDeletedAt)
        XCTAssertNil(manifest.microphoneStemFileName)
        XCTAssertNil(manifest.systemAudioStemFileName)
        XCTAssertEqual(manifest.exports, [])
        XCTAssertEqual(manifest.dirtyFlags, .clean)
    }

    func testSessionManifestDecodesExplicitV1Fixture() throws {
        let manifest = try decodeFixture(SessionManifest.self, named: "session-manifest-v1-with-version")

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.title, "Versioned Session")
        XCTAssertEqual(manifest.recordingSource, .microphoneAndSystemAudio)
        XCTAssertEqual(manifest.microphoneStemFileName, "microphone.caf")
        XCTAssertEqual(manifest.systemAudioStemFileName, "system-audio.caf")
    }

    func testSessionManifestEncodeEmitsCurrentSchemaVersion() throws {
        let original = SessionManifest(
            title: "Round trip",
            status: .ready,
            audioFileName: "audio.caf"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, SessionManifest.currentSchemaVersion)

        let decoded = try makeDecoder().decode(SessionManifest.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, SessionManifest.currentSchemaVersion)
        XCTAssertEqual(decoded.title, original.title)
    }

    func testTranscriptDocumentRoundTripsAgainstFixture() throws {
        let document = try decodeFixture(TranscriptDocument.self, named: "transcript-document-v1")

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.sessionId, UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        XCTAssertEqual(document.languageHint, "en")
        XCTAssertEqual(document.sourceEngine, "TestEngine")
        XCTAssertEqual(document.segments.count, 1)
        XCTAssertEqual(document.segments.first?.text, "Hello world")
        XCTAssertEqual(document.segments.first?.speakerId, "S1")
        XCTAssertEqual(document.speakers.map(\.id), ["S1", "UNK"])
    }

    func testTranscriptDocumentDecodesMinimalFixtureWithDefaults() throws {
        let document = try decodeFixture(TranscriptDocument.self, named: "transcript-document-minimal")

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.sessionId, UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        XCTAssertNil(document.languageHint)
        XCTAssertEqual(document.segments.count, 1)
        XCTAssertEqual(document.segments.first?.text, "Tolerant decode")
        XCTAssertEqual(document.segments.first?.isEdited, false)
        XCTAssertNil(document.segments.first?.speakerId)
        XCTAssertNotNil(document.segments.first?.id)
    }

    func testTranscriptDocumentEncodeEmitsCurrentSchemaVersion() throws {
        let original = TranscriptDocument(
            schemaVersion: 0,
            sessionId: UUID(),
            sourceEngine: "TestEngine",
            segments: [],
            speakers: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, TranscriptDocument.currentSchemaVersion)
    }

    func testAppSettingsEncodeEmitsCurrentSchemaVersion() throws {
        // A settings.json written before versioning decodes as schemaVersion 1;
        // re-encoding it after a mutation must stamp the *current* version, not
        // echo the stale one.
        let original = AppSettings(schemaVersion: 1)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, AppSettings.currentSchemaVersion)

        let decoded = try makeDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, AppSettings.currentSchemaVersion)
    }

    func testAppSettingsDecodesV2Fixture() throws {
        let settings = try decodeFixture(AppSettings.self, named: "app-settings-v2")

        XCTAssertEqual(settings.schemaVersion, 2)
        XCTAssertEqual(settings.selectedRecordingSource, .microphone)
        XCTAssertTrue(settings.isSpeakerDiarizationEnabled)
        XCTAssertEqual(settings.diarizationEngine, .offlineVbx)
        XCTAssertEqual(settings.diarizationExpectedSpeakerCountHint, .auto)
        XCTAssertFalse(settings.isLiveTranscriptionEnabled)
        XCTAssertFalse(settings.isDeleteAudioAfterTranscriptionEnabled)
        XCTAssertEqual(settings.folders, [])
        // Field added after the v2 fixture was captured: absence must decode to the
        // fork default (Automatic), not crash older settings on disk.
        XCTAssertEqual(settings.batchTranscriptionLanguage, .automatic)
    }

    func testAppSettingsBatchTranscriptionLanguageRoundTrips() throws {
        let original = AppSettings(batchTranscriptionLanguage: .english)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoded = try makeDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.batchTranscriptionLanguage, .english)
    }

    // MARK: - Helpers

    private func decodeFixture<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "Missing fixture \(name).json — check that Package.swift bundles the Fixtures directory."
        )
        let data = try Data(contentsOf: url)
        return try makeDecoder().decode(type, from: data)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
