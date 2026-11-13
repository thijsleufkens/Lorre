import Foundation
import XCTest
@testable import LorreCapture

final class RecordingLockTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = makeTemporaryRoot(named: "lock")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testNoLockIsNotLive() {
        XCTAssertFalse(RecordingLock.isLive(in: folder))
        XCTAssertNil(RecordingLock.pid(in: folder))
    }

    func testOwnProcessIsLive() throws {
        try RecordingLock.write(in: folder)
        XCTAssertEqual(RecordingLock.pid(in: folder), ProcessInfo.processInfo.processIdentifier)
        XCTAssertTrue(RecordingLock.isLive(in: folder))
    }

    func testDeadProcessIsNotLive() throws {
        // Start and reap a process; its pid is then free.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        try RecordingLock.write(in: folder, pid: process.processIdentifier)
        XCTAssertFalse(RecordingLock.isLive(in: folder))
    }

    func testUnreadableLockIsNotLive() throws {
        try Data("not json".utf8).write(to: folder.appendingPathComponent(RecordingLock.fileName))
        XCTAssertFalse(RecordingLock.isLive(in: folder))
    }

    func testRemove() throws {
        try RecordingLock.write(in: folder)
        RecordingLock.remove(in: folder)
        XCTAssertFalse(RecordingLock.isLive(in: folder))
        RecordingLock.remove(in: folder) // removing twice is fine
    }
}
