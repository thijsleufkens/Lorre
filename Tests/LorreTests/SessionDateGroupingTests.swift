import Foundation
import XCTest
@testable import Lorre

final class SessionDateGroupingTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return c
    }()

    private func now() -> Date {
        // 2026-05-14 14:00 in Europe/Amsterdam
        var components = DateComponents()
        components.year = 2026; components.month = 5; components.day = 14
        components.hour = 14; components.minute = 0
        components.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        return calendar.date(from: components)!
    }

    private func makeSession(name: String, daysAgo: Int, hour: Int = 10) -> SessionManifest {
        let recorded = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now())!)!
        return SessionManifest(
            title: name,
            status: .ready,
            recordedAt: recorded,
            audioFileName: ""
        )
    }

    func testEmptyListProducesNoGroups() {
        let grouper = SessionDateGrouper(calendar: calendar, now: now())
        XCTAssertTrue(grouper.group([]).isEmpty)
    }

    func testGroupsTodayYesterdayThisWeekAndEarlierInOrder() {
        let grouper = SessionDateGrouper(calendar: calendar, now: now())
        let sessions = [
            makeSession(name: "Earlier-2", daysAgo: 14),
            makeSession(name: "Today-1", daysAgo: 0),
            makeSession(name: "Week-1", daysAgo: 3),
            makeSession(name: "Yesterday-1", daysAgo: 1),
            makeSession(name: "Earlier-1", daysAgo: 9),
            makeSession(name: "Week-2", daysAgo: 5),
        ]

        let groups = grouper.group(sessions)
        let labels = groups.map(\.group)
        XCTAssertEqual(labels, [.today, .yesterday, .thisWeek, .earlier])

        XCTAssertEqual(groups[0].sessions.map(\.title), ["Today-1"])
        XCTAssertEqual(groups[1].sessions.map(\.title), ["Yesterday-1"])
        XCTAssertEqual(groups[2].sessions.map(\.title), ["Week-1", "Week-2"])
        XCTAssertEqual(groups[3].sessions.map(\.title), ["Earlier-2", "Earlier-1"])
    }

    func testPreservesInputOrderWithinGroup() {
        let grouper = SessionDateGrouper(calendar: calendar, now: now())
        let sessions = [
            makeSession(name: "A", daysAgo: 0, hour: 9),
            makeSession(name: "B", daysAgo: 0, hour: 15),
            makeSession(name: "C", daysAgo: 0, hour: 12),
        ]
        let groups = grouper.group(sessions)
        XCTAssertEqual(groups.first?.sessions.map(\.title), ["A", "B", "C"])
    }

    func testDaySixIsThisWeekAndDaySevenIsEarlier() {
        let grouper = SessionDateGrouper(calendar: calendar, now: now())
        let sessions = [
            makeSession(name: "Day6", daysAgo: 6),
            makeSession(name: "Day7", daysAgo: 7),
        ]
        let groups = grouper.group(sessions)
        let map = Dictionary(uniqueKeysWithValues: groups.map { ($0.group, $0.sessions.map(\.title)) })
        XCTAssertEqual(map[.thisWeek], ["Day6"])
        XCTAssertEqual(map[.earlier], ["Day7"])
    }

    func testEmptyGroupsAreOmitted() {
        let grouper = SessionDateGrouper(calendar: calendar, now: now())
        let sessions = [
            makeSession(name: "Today", daysAgo: 0),
            makeSession(name: "Earlier", daysAgo: 30),
        ]
        let groups = grouper.group(sessions)
        XCTAssertEqual(groups.map(\.group), [.today, .earlier])
    }
}
