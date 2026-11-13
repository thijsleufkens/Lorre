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

    public init(endedAt: Date, durationSeconds: Double, trackFailures: [TrackKind: String] = [:]) {
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.trackFailures = trackFailures
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
}
