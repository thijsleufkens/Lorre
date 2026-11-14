import Foundation

/// Locations Lorre owns on disk. Everything is under one root so tests can point it at a temp folder.
public struct LorrePaths: Sendable {
    public let root: URL

    public init(root: URL = LorrePaths.defaultRoot()) {
        self.root = root
    }

    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Lorre", isDirectory: true)
    }

    public var database: URL { root.appendingPathComponent("lorre.sqlite") }

    /// New conversations store their tracks here.
    public var conversations: URL { root.appendingPathComponent("conversations", isDirectory: true) }

    /// The folder holding one conversation's tracks. The folder name is the conversation id.
    public func conversationFolder(_ id: UUID) -> URL {
        conversations.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Path of a file in a conversation folder, relative to `root`, as stored in `Track.relativePath`.
    public func relativeTrackPath(_ id: UUID, fileName: String) -> String {
        "conversations/\(id.uuidString)/\(fileName)"
    }

    /// The pre-rebuild store. Read-only for the new code.
    public var legacySessions: URL { root.appendingPathComponent("sessions", isDirectory: true) }
}
