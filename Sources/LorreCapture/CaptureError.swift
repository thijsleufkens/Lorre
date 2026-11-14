import Foundation

/// What can go wrong while capturing audio. The message is written for the user.
public enum CaptureError: Error, Equatable, Sendable, LocalizedError {
    case startFailed(String)
    case stopFailed(String)
    case permissionDenied(String)
    case alreadyRecording
    case notRecording

    public var message: String {
        switch self {
        case let .startFailed(message), let .stopFailed(message), let .permissionDenied(message):
            message
        case .alreadyRecording:
            "Another recording is already in progress."
        case .notRecording:
            "There is no recording in progress."
        }
    }

    public var errorDescription: String? { message }
}
