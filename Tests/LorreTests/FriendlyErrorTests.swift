import LorreCapture
import LorreCore
import XCTest
@testable import Lorre

final class FriendlyErrorTests: XCTestCase {
    /// The raw messages the code really produces, built from the same sources where possible.
    private var knownMessages: [(raw: String, kind: ViewFormat.ErrorKind)] {
        [
            (LorreError.processingFailed("No speech was found in the recording.").errorDescription!, .noSpeech),
            (CaptureAdvice.silentMicrophone, .silentMicrophone),
            ("Your own voice was not recorded. " + CaptureAdvice.silentMicrophone, .silentMicrophone),
            (LorreError.microphonePermissionDenied.errorDescription!, .silentMicrophone),
            ("The recording was interrupted before it was stopped.", .interrupted),
            ("This recording was found on disk without a conversation and has been restored.", .interrupted),
            ("A recording was interrupted and has been recovered. It is being transcribed now.", .recovered),
            ("3 recordings were interrupted and have been recovered. They are being transcribed now.", .recovered),
            (LorreError.processingFailed("There is no audio to transcribe for this conversation.").errorDescription!, .missingFile),
            ("No audio was captured.", .missingFile),
            ("No audio was captured (microphone: disk full).", .missingFile),
            ("Part of the recording could not be written (system: disk full).", .missingFile),
        ]
    }

    func testEveryKnownMessageMapsToItsSentenceInBothLanguages() {
        for strings in [Strings.dutch, Strings.english] {
            let expected: [ViewFormat.ErrorKind: String] = [
                .noSpeech: strings.errorNoSpeech,
                .silentMicrophone: strings.errorSilentMicrophone,
                .interrupted: strings.errorInterrupted,
                .recovered: strings.errorRecovered,
                .missingFile: strings.errorMissingFile,
            ]
            for (raw, kind) in knownMessages {
                XCTAssertEqual(ViewFormat.errorKind(raw), kind, raw)
                XCTAssertEqual(ViewFormat.friendlyError(raw, strings: strings), expected[kind], raw)
            }
        }
    }

    func testNoMessageGivesNoSentence() {
        XCTAssertNil(ViewFormat.friendlyError(nil, strings: .dutch))
        XCTAssertNil(ViewFormat.friendlyError("", strings: .dutch))
        XCTAssertNil(ViewFormat.friendlyError("  \n", strings: .english))
    }

    func testUnknownMessageGetsTheGenericSentenceWithoutTheRawText() {
        let raw = "Processing failed. ASR manager is not initialized. (code -50, com.apple.coreaudio)"
        for strings in [Strings.dutch, Strings.english] {
            let friendly = ViewFormat.friendlyError(raw, strings: strings)
            XCTAssertEqual(friendly, strings.errorGeneric)
            for fragment in ["ASR", "initialized", "-50", "coreaudio", "Processing failed"] {
                XCTAssertFalse(friendly?.contains(fragment) ?? true, fragment)
            }
        }
    }

    func testFailedStartIsGeneric() {
        let raw = "Could not start recording. No microphone is available."
        XCTAssertEqual(ViewFormat.friendlyError(raw, strings: .dutch), Strings.dutch.errorGeneric)
    }

    func testFriendlySentencesHaveNoTechnicalWordsAndNoRawLeak() {
        for strings in [Strings.dutch, Strings.english] {
            let sentences = [
                strings.errorNoSpeech, strings.errorSilentMicrophone, strings.errorInterrupted,
                strings.errorRecovered, strings.errorMissingFile, strings.errorGeneric,
            ]
            XCTAssertEqual(Set(sentences).count, sentences.count)
            for sentence in sentences {
                for word in ["tcc", "database", "json", "pipeline", "segment", "exception", "error"] {
                    XCTAssertFalse(sentence.lowercased().contains(word), "\(sentence) contains \(word)")
                }
            }
        }
    }

    // MARK: Retry

    private func conv(state: ConversationState, lastError: String? = nil) -> Conversation {
        Conversation(title: "a", state: state, startedAt: Date(timeIntervalSince1970: 1_800_000_000), lastError: lastError)
    }

    func testRetryableConversations() {
        XCTAssertTrue(ViewFormat.isRetryable(conv(state: .interrupted)))
        XCTAssertTrue(ViewFormat.isRetryable(conv(state: .processing, lastError: "x")))
        XCTAssertFalse(ViewFormat.isRetryable(conv(state: .processing)))
        XCTAssertFalse(ViewFormat.isRetryable(conv(state: .recording)))
        XCTAssertFalse(ViewFormat.isRetryable(conv(state: .proposed)))
    }

    func testStateTextSaysBeingWrittenOutWhileQueuedOrRunning() {
        let failed = conv(state: .processing, lastError: "x")
        XCTAssertEqual(ViewFormat.progressLabel(failed, isQueuedOrRunning: false, .dutch), "Uitwerken is mislukt")
        XCTAssertEqual(ViewFormat.progressLabel(failed, isQueuedOrRunning: true, .dutch), "Wordt uitgewerkt")
        let interrupted = conv(state: .interrupted)
        XCTAssertEqual(ViewFormat.progressLabel(interrupted, isQueuedOrRunning: true, .english), "Being transcribed")
        XCTAssertEqual(ViewFormat.progressLabel(interrupted, isQueuedOrRunning: false, .english), "Interrupted")
    }
}
