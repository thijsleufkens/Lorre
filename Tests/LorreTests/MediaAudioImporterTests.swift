import AVFoundation
import XCTest
@testable import Lorre

final class MediaAudioImporterTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mai-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testCopiesAudioOnlyInputVerbatim() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = try await MediaAudioImporter.prepareAudio(from: fixtureURL("sample-audio.m4a"), intoDirectory: dir)
        XCTAssertEqual(name, "audio.m4a")
        let out = dir.appendingPathComponent(name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path(percentEncoded: false)))
        let file = try AVAudioFile(forReading: out)
        XCTAssertGreaterThan(file.length, 0)
    }

    func testExtractsAudioFromVideoToM4A() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = try await MediaAudioImporter.prepareAudio(from: fixtureURL("sample-video.mp4"), intoDirectory: dir)
        XCTAssertEqual(name, "audio.m4a")
        let out = dir.appendingPathComponent(name)
        let file = try AVAudioFile(forReading: out)
        XCTAssertGreaterThan(file.length, 0)
    }

    func testThrowsWhenNoAudioTrack() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            _ = try await MediaAudioImporter.prepareAudio(from: fixtureURL("silent-video.mp4"), intoDirectory: dir)
            XCTFail("expected noAudioTrack")
        } catch let error as MediaAudioImporter.ImportError {
            XCTAssertEqual(error, .noAudioTrack)
        }
    }
}
