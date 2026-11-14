import AVFoundation
import LorreCapture
import LorreCore
import XCTest
@testable import Lorre

@MainActor
final class AudioLocatorTests: XCTestCase {
    private var root: URL!
    private var paths: LorrePaths!
    private let id = UUID()

    override func setUpWithError() throws {
        root = makeTemporaryRoot(named: "locator")
        paths = LorrePaths(root: root)
        try FileManager.default.createDirectory(at: paths.conversationFolder(id), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func track(_ kind: TrackKind, bytes: Int?) throws -> Track {
        if let bytes {
            try Data(repeating: 1, count: bytes)
                .write(to: paths.conversationFolder(id).appendingPathComponent(kind.fileName))
        }
        return Track(conversationId: id, kind: kind, relativePath: paths.relativeTrackPath(id, fileName: kind.fileName))
    }

    private func name(_ url: URL?) -> String? { url?.lastPathComponent }

    func testMixWinsOverTheStems() throws {
        let tracks = [try track(.system, bytes: 10), try track(.microphone, bytes: 10), try track(.mix, bytes: 10)]
        XCTAssertEqual(name(AudioLocator.playableURL(tracks: tracks, paths: paths)), "mix.caf")
    }

    func testMicrophoneComesBeforeSystem() throws {
        let tracks = [try track(.system, bytes: 10), try track(.microphone, bytes: 10)]
        XCTAssertEqual(name(AudioLocator.playableURL(tracks: tracks, paths: paths)), "microphone.caf")
    }

    func testEmptyAndMissingFilesAreSkipped() throws {
        let tracks = [try track(.mix, bytes: 0), try track(.microphone, bytes: nil), try track(.system, bytes: 10)]
        XCTAssertEqual(name(AudioLocator.playableURL(tracks: tracks, paths: paths)), "system-audio.caf")
    }

    func testNothingPlayableGivesNil() throws {
        XCTAssertNil(AudioLocator.playableURL(tracks: [], paths: paths))
        let tracks = [try track(.mix, bytes: 0), try track(.system, bytes: nil)]
        XCTAssertNil(AudioLocator.playableURL(tracks: tracks, paths: paths))
    }

    func testDeviceTracksAreNotPlayedDirectly() throws {
        XCTAssertNil(AudioLocator.playableURL(tracks: [try track(.device, bytes: 10)], paths: paths))
    }
}

@MainActor
final class EvidencePlayerTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = makeTemporaryRoot(named: "player")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func testPlaysAShortFileAndStops() throws {
        let url = root.appendingPathComponent("tone.caf")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let samples = (0..<(16_000 * 3)).map { Float(sin(Double($0) * 0.05)) * 0.2 }
        try RecorderAudioUtilities.write(samples: samples, to: url, format: format)

        let player = EvidencePlayer()
        XCTAssertFalse(player.isPlaying)
        player.play(url: url, startMs: 500, endMs: 2_000)
        XCTAssertTrue(player.isPlaying)
        player.stop()
        XCTAssertFalse(player.isPlaying)
    }

    func testNewPlaybackReplacesTheOldAndStopsAtTheEnd() async throws {
        let url = root.appendingPathComponent("tone.caf")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        try RecorderAudioUtilities.write(samples: Array(repeating: 0.1, count: 16_000 * 2), to: url, format: format)

        let player = EvidencePlayer()
        player.play(url: url, startMs: 0, endMs: nil)
        player.play(url: url, startMs: 0, endMs: 200)
        XCTAssertTrue(player.isPlaying)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(player.isPlaying, "playback ends at the end of the range")
    }

    func testUnreadableFileLeavesItNotPlaying() throws {
        let url = root.appendingPathComponent("broken.caf")
        try Data("not audio".utf8).write(to: url)
        let player = EvidencePlayer()
        player.play(url: url, startMs: 0, endMs: nil)
        XCTAssertFalse(player.isPlaying)
        player.play(url: root.appendingPathComponent("missing.caf"), startMs: 0, endMs: nil)
        XCTAssertFalse(player.isPlaying)
    }

    func testStartBeyondTheEndDoesNotPlay() throws {
        let url = root.appendingPathComponent("tone.caf")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        try RecorderAudioUtilities.write(samples: Array(repeating: 0.1, count: 16_000), to: url, format: format)
        let player = EvidencePlayer()
        player.play(url: url, startMs: 60_000, endMs: nil)
        XCTAssertFalse(player.isPlaying)
    }
}
