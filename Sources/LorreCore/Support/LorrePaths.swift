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

    /// The pre-rebuild store. Read-only for the new code.
    public var legacySessions: URL { root.appendingPathComponent("sessions", isDirectory: true) }
}
