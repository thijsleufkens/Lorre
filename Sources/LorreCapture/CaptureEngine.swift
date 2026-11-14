import Foundation
import LorreCore

public struct CaptureStart: Equatable, Sendable {
    public var startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }
}

public struct CaptureStop: Equatable, Sendable {
    public var endedAt: Date
    public var durationSeconds: Double
    /// Tracks whose writer reported an error. Their files are kept as far as they got.
    public var trackFailures: [TrackKind: String]
    /// Tracks that were written but contain nothing except digital silence. For the microphone
    /// this means macOS is withholding the input, almost always a missing permission.
    public var silentTracks: Set<TrackKind>

    public init(
        endedAt: Date,
        durationSeconds: Double,
        trackFailures: [TrackKind: String] = [:],
        silentTracks: Set<TrackKind> = []
    ) {
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.trackFailures = trackFailures
        self.silentTracks = silentTracks
    }
}

/// Records audio into a folder, one file per track (`TrackKind.fileName`).
///
/// The contract that keeps recordings safe:
/// - `start` either succeeds with every requested track running, or throws and leaves no files behind;
/// - `stop` never throws and never deletes anything: a track that failed is reported, not removed.
public protocol CaptureEngine: Sendable {
    func start(source: CaptureSource, into folder: URL) async throws -> CaptureStart
    func stop() async -> CaptureStop
    /// Current input level per track, 0...1.
    func levels() async -> [TrackKind: Double]
    /// Tracks that have delivered only digital silence for long enough to be sure something is wrong.
    func silentTracks() async -> Set<TrackKind>
}

public extension CaptureEngine {
    func silentTracks() async -> Set<TrackKind> { [] }
}

public enum CaptureAdvice {
    /// What to tell the user when the microphone delivers nothing but zeros.
    public static let silentMicrophone =
        "Lorre is not receiving any sound from the microphone. Allow Lorre under System Settings → Privacy & Security → Microphone (switch it off and on again if it is already allowed), then start a new recording."
}
