import AVFoundation
import LorreCapture
import LorreCore
import XCTest
@testable import Lorre

/// Fakes that tell the tracks apart by length: the microphone track is 2 s, the system track 3 s,
/// the mix of the two 3 s as well.
private final class TrackFakes: @unchecked Sendable {
    private let lock = NSLock()
    private var _transcribed: [Int] = []
    private var _diarized: [Int] = []
    var failOnMicrophone = false

    var transcribedSeconds: [Int] { lock.withLock { _transcribed } }
    var diarizedSeconds: [Int] { lock.withLock { _diarized } }

    static func seconds(_ url: URL) -> Int {
        guard let file = try? AVAudioFile(forReading: url) else { return -1 }
        return Int((Double(file.length) / file.fileFormat.sampleRate).rounded())
    }

    struct Transcription: TranscriptionService {
        let fakes: TrackFakes
        func ensureModelsReady(onProgress: (@Sendable (ProcessingUpdate) async -> Void)?) async throws {}
        func setVocabularyBoostingConfiguration(_ configuration: VocabularyBoostingConfiguration) async {}
        func setBatchTranscriptionLanguage(_ language: BatchTranscriptionLanguage) async {}
        func transcribe(url: URL, sessionTitle: String, source: RecordingSource) async throws -> TranscriptionResult {
            let seconds = TrackFakes.seconds(url)
            fakes.lock.withLock { fakes._transcribed.append(seconds) }
            func utterance(_ start: Int, _ end: Int, _ text: String) -> TranscriptionUtterance {
                TranscriptionUtterance(startMs: start, endMs: end, text: text, confidence: 0.9)
            }
            if seconds == 2 {
                if fakes.failOnMicrophone { throw LorreError.processingFailed("simulated microphone failure") }
                return TranscriptionResult(engineName: "fake", utterances: [
                    utterance(0, 900, "hello from me"),
                    utterance(3000, 3900, "my second line"),
                    utterance(5000, 5900, "   "),
                ])
            }
            return TranscriptionResult(engineName: "fake", utterances: [
                utterance(1000, 1900, "first from them"),
                utterance(3000, 3900, "second from someone else"),
            ])
        }
    }

    struct Diarization: SpeakerDiarizationService {
        let fakes: TrackFakes
        func ensureModelsReady(onProgress: (@Sendable (ProcessingUpdate) async -> Void)?) async throws {}
        func setKnownSpeakers(_ speakers: [KnownSpeaker]) async {}
        func setDiarizationEngine(_ engine: DiarizationEngine) async {}
        func diarize(
            url: URL, expectedDurationSeconds: Double?, expectedSpeakers: DiarizationSpeakerCountHint
        ) async throws -> DiarizationResult? {
            fakes.lock.withLock { fakes._diarized.append(TrackFakes.seconds(url)) }
            return DiarizationResult(spans: [
                DiarizationSpan(startMs: 0, endMs: 2500, speakerId: "S1"),
                DiarizationSpan(startMs: 2500, endMs: 6000, speakerId: "S2"),
            ])
        }
    }
}

final class PerTrackProcessingTests: XCTestCase {
    private var root: URL!
    private var paths: LorrePaths!
    private var database: LorreDatabase!
    private var store: ConversationStore!
    private var fakes: TrackFakes!

    override func setUpWithError() throws {
        root = makeTemporaryRoot(named: "pertrack")
        paths = LorrePaths(root: root)
        database = try LorreDatabase(url: paths.database)
        store = ConversationStore(database: database)
        fakes = TrackFakes()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func processor() -> ConversationProcessor {
        ConversationProcessor(
            paths: paths, database: database,
            transcription: TrackFakes.Transcription(fakes: fakes),
            diarization: TrackFakes.Diarization(fakes: fakes)
        )
    }

    private func options(perTrack: Bool = true) -> ConversationProcessor.Options {
        var options = ConversationProcessor.Options()
        options.writesDraftRecord = false
        options.perTrack = perTrack
        return options
    }

    private func write(_ url: URL, seconds: Double, silent: Bool = false) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let samples = (0..<Int(seconds * 16_000)).map { silent ? Float(0) : Float(sin(Double($0) * 0.05)) * 0.4 }
        try RecorderAudioUtilities.write(samples: samples, to: url, format: format)
    }

    private func makeConversation(
        microphoneSeconds: Double? = 2,
        systemSeconds: Double? = 3,
        silentMicrophone: Bool = false
    ) throws -> Conversation {
        let conversation = Conversation(
            title: "Call", state: .processing, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationSeconds: 3, captureSource: .microphoneAndSystemAudio
        )
        try store.save(conversation)
        let folder = paths.conversationFolder(conversation.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var tracks: [Track] = []
        for (kind, seconds) in [(TrackKind.microphone, microphoneSeconds), (.system, systemSeconds)] {
            guard let seconds else { continue }
            try write(folder.appendingPathComponent(kind.fileName), seconds: seconds, silent: kind == .microphone && silentMicrophone)
            tracks.append(Track(
                conversationId: conversation.id, kind: kind,
                relativePath: paths.relativeTrackPath(conversation.id, fileName: kind.fileName)
            ))
        }
        try store.saveTracks(tracks)
        return conversation
    }

    private func texts(of conversation: Conversation) throws -> [(String, String?)] {
        let participants = try store.participants(conversationId: conversation.id)
        return try store.currentSegments(conversationId: conversation.id).map { segment in
            (segment.text, participants.first { $0.id == segment.participantId }?.name)
        }
    }

    private var defaultUserName: String { PerTrackTranscript.defaultUserName(LorreLanguage.current) }
    private func speaker(_ n: Int) -> String { PerTrackTranscript.otherName(n - 1, LorreLanguage.current) }

    // MARK: Two tracks

    func testTwoTracksGiveUserSegmentsFromTheMicrophoneAndOthersFromTheSystemTrack() async throws {
        let conversation = try makeConversation()
        let processed = try await processor().process(conversation.id, options: options())
        XCTAssertEqual(processed.state, .proposed)

        let segments = try texts(of: conversation)
        XCTAssertEqual(segments.map(\.0), ["hello from me", "first from them", "second from someone else", "my second line"])
        // At 3000 ms both sides start: the system segment comes first.
        XCTAssertEqual(segments.map(\.1), [defaultUserName, speaker(1), speaker(2), defaultUserName])

        let participants = try store.participants(conversationId: conversation.id)
        XCTAssertEqual(participants.count, 3)
        XCTAssertEqual(participants.filter(\.isUser).map(\.name), [defaultUserName])
        // Speech recognition ran on each track; speakers were only looked for on the system track.
        XCTAssertEqual(fakes.transcribedSeconds.sorted(), [2, 3])
        XCTAssertEqual(fakes.diarizedSeconds, [3])
    }

    func testEmptyMicrophoneSegmentIsDropped() async throws {
        let conversation = try makeConversation()
        _ = try await processor().process(conversation.id, options: options())
        XCTAssertFalse(try texts(of: conversation).contains { $0.0.trimmingCharacters(in: .whitespaces).isEmpty })
        XCTAssertEqual(try store.currentSegments(conversationId: conversation.id).count, 4)
    }

    func testMixIsStillProducedAndTracksAreUntouched() async throws {
        let conversation = try makeConversation()
        let folder = paths.conversationFolder(conversation.id)
        let before = try ["microphone.caf", "system-audio.caf"].map { try Data(contentsOf: folder.appendingPathComponent($0)) }
        _ = try await processor().process(conversation.id, options: options())

        let files = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        XCTAssertEqual(files, ["microphone.caf", "system-audio.caf", "mix.caf", "transcript.md"])
        XCTAssertEqual(Set(try store.tracks(conversationId: conversation.id).map(\.kind)), [.microphone, .system, .mix])
        let after = try ["microphone.caf", "system-audio.caf"].map { try Data(contentsOf: folder.appendingPathComponent($0)) }
        XCTAssertEqual(before, after)
        let markdown = try String(contentsOf: folder.appendingPathComponent("transcript.md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("first from them"))
    }

    func testNameFromTheSettingsIsUsed() async throws {
        try SettingsStore(database: database).set("  Thijs ", for: .userName)
        let conversation = try makeConversation()
        _ = try await processor().process(conversation.id, options: options())
        XCTAssertEqual(try store.participants(conversationId: conversation.id).first(where: \.isUser)?.name, "Thijs")
        XCTAssertEqual(try texts(of: conversation).first?.1, "Thijs")
    }

    func testUserParticipantIsReusedAndNothingIsDuplicatedOnReprocessing() async throws {
        let conversation = try makeConversation()
        _ = try await processor().process(conversation.id, options: options())
        let first = try store.participants(conversationId: conversation.id)

        // A later change of the setting does not rename or duplicate the existing user.
        try SettingsStore(database: database).set("Someone Else", for: .userName)
        _ = try await processor().process(conversation.id, options: options())
        let second = try store.participants(conversationId: conversation.id)

        XCTAssertEqual(Set(second.map(\.id)), Set(first.map(\.id)))
        XCTAssertEqual(second.filter(\.isUser).count, 1)
        XCTAssertEqual(try store.currentSegments(conversationId: conversation.id).count, 4)
    }

    func testAnExistingUserParticipantIsReusedForTheMicrophone() async throws {
        let conversation = try makeConversation()
        let existing = Participant(conversationId: conversation.id, name: "Thijs Leufkens", isUser: true)
        try store.saveParticipants([existing])
        _ = try await processor().process(conversation.id, options: options())

        let participants = try store.participants(conversationId: conversation.id)
        XCTAssertEqual(participants.filter(\.isUser).map(\.id), [existing.id])
        XCTAssertEqual(try texts(of: conversation).first?.1, "Thijs Leufkens")
    }

    func testWithoutDiarizationTheSystemTrackIsOneParticipant() async throws {
        let conversation = try makeConversation()
        var options = options()
        options.enableDiarization = false
        _ = try await processor().process(conversation.id, options: options)

        let others = try store.participants(conversationId: conversation.id).filter { !$0.isUser }
        XCTAssertEqual(others.map(\.name), [speaker(1)])
        XCTAssertEqual(fakes.diarizedSeconds, [])
    }

    // MARK: Everything else keeps the old behaviour

    func testSingleTrackUsesTheMixPath() async throws {
        let conversation = try makeConversation(systemSeconds: nil)
        _ = try await processor().process(conversation.id, options: options())
        XCTAssertFalse(try store.participants(conversationId: conversation.id).contains(where: \.isUser))
        XCTAssertEqual(fakes.transcribedSeconds, [2])
        XCTAssertEqual(fakes.diarizedSeconds, [2])
    }

    func testSilentMicrophoneUsesTheMixPath() async throws {
        let conversation = try makeConversation(silentMicrophone: true)
        let processed = try await processor().process(conversation.id, options: options())
        XCTAssertEqual(processed.state, .proposed)
        XCTAssertFalse(try store.participants(conversationId: conversation.id).contains(where: \.isUser))
        XCTAssertEqual(fakes.transcribedSeconds, [3], "one pass, on the mix")
    }

    func testPerTrackOffUsesTheMixPath() async throws {
        let conversation = try makeConversation()
        _ = try await processor().process(conversation.id, options: options(perTrack: false))
        XCTAssertFalse(try store.participants(conversationId: conversation.id).contains(where: \.isUser))
        XCTAssertEqual(fakes.transcribedSeconds, [3])
        XCTAssertEqual(fakes.diarizedSeconds, [3])
    }

    func testPerTrackFailureFallsBackToTheMixAndRecordsNothing() async throws {
        fakes.failOnMicrophone = true
        let conversation = try makeConversation()
        let processed = try await processor().process(conversation.id, options: options())

        XCTAssertEqual(processed.state, .proposed)
        XCTAssertNil(processed.lastError)
        XCTAssertNil(try store.conversation(id: conversation.id)?.lastError)
        XCTAssertFalse(try store.currentSegments(conversationId: conversation.id).isEmpty)
        XCTAssertFalse(try store.participants(conversationId: conversation.id).contains(where: \.isUser))
        XCTAssertEqual(fakes.transcribedSeconds, [2, 3], "the failed microphone pass, then the mix")
    }

    func testFailureOfBothPathsIsRecorded() async throws {
        fakes.failOnMicrophone = true
        // With a 2 s system track the mix is 2 s as well, so the failing fake rejects it too.
        let conversation = try makeConversation(systemSeconds: 2)
        do {
            _ = try await processor().process(conversation.id, options: options())
            XCTFail("processing should fail")
        } catch {}
        XCTAssertEqual(
            try store.conversation(id: conversation.id)?.lastError?.contains("simulated microphone failure"), true
        )
        XCTAssertNil(try store.currentTranscriptVersion(conversationId: conversation.id))
    }

    // MARK: Pure parts

    func testSegmentsWithoutASpeakerJoinTheSpeakerBefore() {
        let id = UUID()
        func segment(_ start: Int, _ speaker: String?) -> TranscriptSegment {
            TranscriptSegment(startMs: start, endMs: start + 500, text: "t\(start)", speakerId: speaker)
        }
        let system = TranscriptDocument(
            sessionId: id, sourceEngine: "fake",
            segments: [segment(0, "UNK"), segment(1000, "S7"), segment(2000, "UNK"), segment(3000, "S3")],
            speakers: []
        )
        let user = Participant(conversationId: id, name: "Me", isUser: true, sourceLabel: "user")
        let merged = PerTrackTranscript.merge(
            microphone: TranscriptDocument(sessionId: id, sourceEngine: "fake", segments: [], speakers: []),
            system: system, conversationId: id, user: user, language: .english
        )
        XCTAssertEqual(merged.segments.map(\.speakerId), ["other-1", "other-1", "other-1", "other-2"])
        XCTAssertEqual(merged.speakers.map(\.displayName), ["Me", "Speaker 1", "Speaker 2"])
    }
}
