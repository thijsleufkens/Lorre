import AVFoundation
import Foundation
import LorreCapture
import LorreCore

/// The pure parts of per-track processing: which conversations qualify, how two transcripts become
/// one, and who the participants are. The processor does the I/O around them.
enum PerTrackTranscript {
    /// Engine labels of the participants this produces. Stored as `Participant.sourceLabel`, so that
    /// processing a conversation again finds the same participants. None starts with "S", which the
    /// speaker model reads as an anonymous diarization label.
    static let userLabel = "user"
    static func otherLabel(_ index: Int) -> String { "other-\(index + 1)" }

    /// Audio below this peak counts as silence (about -66 dBFS).
    static let silencePeak: Float = 0.0005

    // MARK: Eligibility

    /// The microphone and system track when both can be read and both contain sound. A silent,
    /// damaged, empty or missing track means this conversation is not processed per track.
    static func eligibleTracks(tracks: [Track], paths: LorrePaths) -> (microphone: URL, system: URL)? {
        guard let microphone = ConversationProcessor.trackURL(.microphone, in: tracks, paths: paths),
              let system = ConversationProcessor.trackURL(.system, in: tracks, paths: paths),
              RecordingRecovery.trackDuration(microphone) != nil,
              RecordingRecovery.trackDuration(system) != nil,
              hasSignal(microphone), hasSignal(system)
        else { return nil }
        return (microphone, system)
    }

    /// Whether the file has any sample above the silence threshold. Stops at the first one.
    static func hasSignal(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 32_768)
        else { return false }
        while file.framePosition < file.length {
            buffer.frameLength = 0
            guard (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 else { return false }
            guard let channels = buffer.floatChannelData else { return false }
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for frame in 0..<Int(buffer.frameLength) where abs(samples[frame]) > silencePeak {
                    return true
                }
            }
        }
        return false
    }

    // MARK: Participants

    static func defaultUserName(_ language: LorreLanguage) -> String {
        language == .dutch ? "Ik" : "Me"
    }

    static func otherName(_ index: Int, _ language: LorreLanguage) -> String {
        (language == .dutch ? "Spreker " : "Speaker ") + "\(index + 1)"
    }

    /// The conversation's user participant: the existing one, or a new one named after the setting
    /// (or "Ik" / "Me"). Created once; processing again finds it.
    static func ensureUserParticipant(
        conversationId: UUID,
        configuredName: String?,
        language: LorreLanguage,
        store: ConversationStore
    ) throws -> Participant {
        if var existing = try store.participants(conversationId: conversationId).first(where: \.isUser) {
            if existing.sourceLabel == nil {
                existing.sourceLabel = userLabel
                try store.saveParticipants([existing])
            }
            return existing
        }
        let trimmed = configuredName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let participant = Participant(
            conversationId: conversationId,
            name: trimmed.isEmpty ? defaultUserName(language) : trimmed,
            isUser: true,
            sourceLabel: userLabel
        )
        try store.saveParticipants([participant])
        return participant
    }

    // MARK: Merge

    /// One transcript out of the two. Microphone segments belong to the user and are dropped when
    /// their text is empty. System segments get "other" speakers in order of first appearance;
    /// a segment without a speaker joins the one before it. Ordered by start time, system first on
    /// ties.
    static func merge(
        microphone: TranscriptDocument,
        system: TranscriptDocument,
        conversationId: UUID,
        user: Participant,
        language: LorreLanguage
    ) -> TranscriptDocument {
        let userLabel = user.sourceLabel ?? Self.userLabel

        let micSegments = microphone.segments.compactMap { segment -> TranscriptSegment? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            var copy = segment
            copy.text = text
            copy.speakerId = userLabel
            copy.sourceSpeakerId = userLabel
            return copy
        }

        let systemSorted = system.segments.sorted { ($0.startMs, $0.endMs) < ($1.startMs, $1.endMs) }
        var order: [String] = []
        for segment in systemSorted {
            guard let id = segment.speakerId, id != "UNK", !order.contains(id) else { continue }
            order.append(id)
        }
        let speakerCount = max(order.count, 1)
        var lastIndex: Int?
        let systemSegments = systemSorted.map { segment -> TranscriptSegment in
            let index: Int
            if let id = segment.speakerId, let known = order.firstIndex(of: id) {
                index = known
            } else {
                index = lastIndex ?? 0
            }
            lastIndex = index
            var copy = segment
            copy.speakerId = otherLabel(index)
            copy.sourceSpeakerId = otherLabel(index)
            return copy
        }

        // `sorted` is not stable; the key makes the order complete, and a system segment (flag 0)
        // precedes a microphone segment (flag 1) that starts at the same moment.
        struct Entry { var segment: TranscriptSegment; var isMicrophone: Bool }
        let entries = (systemSegments.map { Entry(segment: $0, isMicrophone: false) }
            + micSegments.map { Entry(segment: $0, isMicrophone: true) })
            .sorted {
                ($0.segment.startMs, $0.isMicrophone ? 1 : 0, $0.segment.endMs)
                    < ($1.segment.startMs, $1.isMicrophone ? 1 : 0, $1.segment.endMs)
            }

        var speakers = [SpeakerProfile(
            id: userLabel, displayName: user.name, styleVariant: .filled, isUserRenamed: false
        )]
        let variants: [SpeakerBadgeVariant] = [.outline, .doubleOutline, .dashed]
        let used = Set(systemSegments.compactMap(\.speakerId))
        for index in 0..<speakerCount where used.contains(otherLabel(index)) {
            speakers.append(SpeakerProfile(
                id: otherLabel(index),
                displayName: otherName(index, language),
                styleVariant: variants[index % variants.count],
                isUserRenamed: false
            ))
        }

        return TranscriptDocument(
            sessionId: conversationId,
            languageHint: system.languageHint ?? microphone.languageHint,
            sourceEngine: system.sourceEngine,
            segments: entries.map(\.segment),
            speakers: speakers,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: Progress

    static func scale(_ update: ProcessingUpdate, into range: ClosedRange<Double>) -> ProcessingUpdate {
        var scaled = update
        let local = min(max(update.fraction ?? 0, 0), 1)
        scaled.fraction = range.lowerBound + (range.upperBound - range.lowerBound) * local
        return scaled
    }
}
