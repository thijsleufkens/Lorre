import Foundation

/// Marks a conversation folder as being recorded right now, by which process.
///
/// Recovery uses it to tell a recording in progress from one that was abandoned by a crash.
public enum RecordingLock {
    public static let fileName = "recording.lock"

    struct Contents: Codable {
        var pid: Int32
        var startedAt: Date
    }

    public static func write(
        in folder: URL,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        startedAt: Date = Date()
    ) throws {
        let data = try JSONEncoder().encode(Contents(pid: pid, startedAt: startedAt))
        try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
    }

    /// The process id in the lock, or nil when there is no readable lock.
    public static func pid(in folder: URL) -> Int32? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return (try? JSONDecoder().decode(Contents.self, from: data))?.pid
    }

    public static func remove(in folder: URL) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(fileName))
    }

    /// True only when the lock names a process that is still running.
    public static func isLive(in folder: URL) -> Bool {
        guard let pid = pid(in: folder), pid > 0 else { return false }
        // Signal 0 checks for existence without sending anything. EPERM means it exists but is not ours.
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
