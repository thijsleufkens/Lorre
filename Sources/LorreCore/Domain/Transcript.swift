import Foundation

public enum TrackKind: String, Codable, CaseIterable, Sendable {
    case mix, microphone, system, device

    /// The file a track of this kind is written to inside a conversation folder.
    public var fileName: String {
        switch self {
        case .mix: "mix.caf"
        case .microphone: "microphone.caf"
        case .system: "system-audio.caf"
        case .device: "device.caf"
        }
    }
}

/// What a recording captures.
public enum CaptureSource: String, Codable, CaseIterable, Sendable {
    case microphone, systemAudio, microphoneAndSystemAudio

    public var includesMicrophone: Bool { self != .systemAudio }
    public var includesSystemAudio: Bool { self != .microphone }

    /// The tracks a recording from this source produces.
    public var trackKinds: [TrackKind] {
        switch self {
        case .microphone: [.microphone]
        case .systemAudio: [.system]
        case .microphoneAndSystemAudio: [.microphone, .system]
        }
    }
}

/// One captured audio source of a conversation.
public struct Track: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var conversationId: UUID
    public var kind: TrackKind
    /// Path relative to `LorrePaths.root`.
    public var relativePath: String

    public init(id: UUID = UUID(), conversationId: UUID, kind: TrackKind, relativePath: String) {
        self.id = id
        self.conversationId = conversationId
        self.kind = kind
        self.relativePath = relativePath
    }
}

/// One transcription pass over a conversation, with the engine that produced it.
/// Re-processing adds a version; exactly one version per conversation is current.
public struct TranscriptVersion: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var conversationId: UUID
    public var engine: String
    public var modelVersion: String?
    public var settingsJSON: String?
    public var languageHint: String?
    public var isCurrent: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        conversationId: UUID,
        engine: String,
        modelVersion: String? = nil,
        settingsJSON: String? = nil,
        languageHint: String? = nil,
        isCurrent: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.engine = engine
        self.modelVersion = modelVersion
        self.settingsJSON = settingsJSON
        self.languageHint = languageHint
        self.isCurrent = isCurrent
        self.createdAt = createdAt
    }
}

public struct Segment: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var transcriptVersionId: UUID
    public var participantId: UUID?
    public var startMs: Int
    public var endMs: Int
    public var text: String
    public var confidence: Double?
    public var isEdited: Bool

    public init(
        id: UUID = UUID(),
        transcriptVersionId: UUID,
        participantId: UUID? = nil,
        startMs: Int,
        endMs: Int,
        text: String,
        confidence: Double? = nil,
        isEdited: Bool = false
    ) {
        self.id = id
        self.transcriptVersionId = transcriptVersionId
        self.participantId = participantId
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.confidence = confidence
        self.isEdited = isEdited
    }
}
