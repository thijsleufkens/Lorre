import Foundation
import XCTest
@testable import LorreCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/legacy/\(name)", withExtension: "json"),
            "missing fixture \(name)"
        )
        return try Data(contentsOf: url)
    }
}

/// A throwaway application-support root with helpers to build legacy session folders in it.
final class TemporaryRoot {
    let paths: LorrePaths

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LorreCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = LorrePaths(root: root)
    }

    deinit {
        try? FileManager.default.removeItem(at: paths.root)
    }

    @discardableResult
    func addLegacySession(
        folder: String,
        manifest: Data,
        transcript: Data? = nil,
        files: [String] = []
    ) throws -> URL {
        let url = paths.legacySessions.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try manifest.write(to: url.appendingPathComponent("session.json"))
        try transcript?.write(to: url.appendingPathComponent("transcript.json"))
        for file in files {
            try Data("audio".utf8).write(to: url.appendingPathComponent(file))
        }
        return url
    }

    /// Every file under the legacy folder with its size and modification date.
    func legacySnapshot() throws -> [String: String] {
        var snapshot: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(
            at: paths.legacySessions,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            snapshot[url.path] = "\(values.fileSize ?? -1)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        return snapshot
    }
}

func makeConversation(
    id: UUID = UUID(),
    title: String = "Test",
    startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> Conversation {
    Conversation(
        id: id,
        title: title,
        type: .network,
        state: .proposed,
        startedAt: startedAt,
        durationSeconds: 60,
        calendarEventId: "event-1",
        importedAt: nil,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
    )
}
