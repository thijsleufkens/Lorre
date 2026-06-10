import Foundation
import XCTest
@testable import Lorre

final class PersistenceHygieneTests: XCTestCase {
    func testAtomicFileWriterCleansUpTempFileWhenCommitFails() throws {
        let directory = makeTemporaryRoot(named: "atomic-writer")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // An immutable target makes the final replace fail after the temp
        // file was already written.
        let target = directory.appendingPathComponent("payload.json")
        try Data("old".utf8).write(to: target)
        let targetPath = target.path(percentEncoded: false)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: targetPath)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: targetPath) }

        XCTAssertThrowsError(try AtomicFileWriter.write(Data("x".utf8), to: target))

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertEqual(leftovers, [], "A failed commit must not leave .tmp files behind")
    }

    func testReplacingReferenceClipWithDifferentExtensionRemovesOldClip() async throws {
        let root = makeTemporaryRoot(named: "known-speakers")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnownSpeakerStore(baseURL: root)

        let m4aSource = root.appendingPathComponent("clip.m4a")
        let wavSource = root.appendingPathComponent("clip.wav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("m4a".utf8).write(to: m4aSource)
        try Data("wav".utf8).write(to: wavSource)

        let enrollment = KnownSpeakerEnrollmentData(embedding: [0.1], durationSeconds: 1, sampleRate: 16_000)
        let speaker = try await store.saveNewSpeaker(
            displayName: "Thijs",
            embedding: [0.1],
            referenceAudioURL: m4aSource,
            enrollmentData: enrollment
        )

        let samplesDirectory = root.appendingPathComponent("known-speaker-samples", isDirectory: true)
        let oldClip = samplesDirectory.appendingPathComponent("\(speaker.id).m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldClip.path(percentEncoded: false)))

        _ = try await store.updateSpeaker(
            speaker,
            replacingReferenceAudioAt: wavSource,
            enrollmentData: enrollment
        )

        let newClip = samplesDirectory.appendingPathComponent("\(speaker.id).wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newClip.path(percentEncoded: false)))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: oldClip.path(percentEncoded: false)),
            "Replacing a clip with a different extension must not leave the old file behind forever"
        )
    }
}
