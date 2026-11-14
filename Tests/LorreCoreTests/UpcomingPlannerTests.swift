import XCTest
@testable import LorreCore

final class UpcomingPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func meeting(_ id: String, start: TimeInterval, length: TimeInterval = 3600, names: [String] = []) -> UpcomingMeeting {
        UpcomingMeeting(
            eventId: id, title: id, start: now.addingTimeInterval(start),
            end: now.addingTimeInterval(start + length), attendeeNames: names
        )
    }

    // MARK: comingUp

    func testEndedMeetingIsLeftOutAndOneEndingExactlyNowToo() {
        let ended = meeting("ended", start: -7200, length: 3600)
        let endsNow = meeting("endsNow", start: -3600, length: 3600)
        let running = meeting("running", start: -60)
        XCTAssertEqual(UpcomingPlanner.comingUp(meetings: [ended, endsNow, running], now: now).map(\.eventId), ["running"])
    }

    func testStartWithin24HoursCountsBeyondDoesNot() {
        let edge = meeting("edge", start: 24 * 3600)
        let late = meeting("late", start: 25 * 3600)
        XCTAssertEqual(UpcomingPlanner.comingUp(meetings: [late, edge], now: now).map(\.eventId), ["edge"])
    }

    func testSortedByStartAndLimited() {
        let items = [meeting("c", start: 3000), meeting("a", start: 100), meeting("d", start: 4000), meeting("b", start: 200)]
        XCTAssertEqual(UpcomingPlanner.comingUp(meetings: items, now: now).map(\.eventId), ["a", "b", "c"])
        XCTAssertEqual(UpcomingPlanner.comingUp(meetings: items, now: now, limit: 1).map(\.eventId), ["a"])
        XCTAssertEqual(UpcomingPlanner.comingUp(meetings: items, now: now, limit: 0), [])
    }

    // MARK: current

    func testCurrentUsesFiveMinuteToleranceBeforeStart() {
        XCTAssertEqual(UpcomingPlanner.current(meetings: [meeting("m", start: 300)], now: now)?.eventId, "m")
        XCTAssertNil(UpcomingPlanner.current(meetings: [meeting("m", start: 301)], now: now))
    }

    func testCurrentIsNilAfterTheEnd() {
        XCTAssertNil(UpcomingPlanner.current(meetings: [meeting("m", start: -3600, length: 3600)], now: now))
        XCTAssertNotNil(UpcomingPlanner.current(meetings: [meeting("m", start: -3599, length: 3600)], now: now))
    }

    func testOverlappingMeetingsPickTheOneThatStartedLast() {
        let long = meeting("long", start: -1800, length: 7200)
        let short = meeting("short", start: -600, length: 1800)
        let soon = meeting("soon", start: 120)
        XCTAssertEqual(UpcomingPlanner.current(meetings: [long, short], now: now)?.eventId, "short")
        XCTAssertEqual(UpcomingPlanner.current(meetings: [long, short, soon], now: now)?.eventId, "soon")
    }

    // MARK: matchPeople

    private func summary(_ name: String, open: Int) -> PersonSummary {
        PersonSummary(person: Person(name: name), conversationCount: 1, lastConversationAt: nil, openCount: open)
    }

    func testMatchesFullNameIgnoringCaseAndDiacritics() {
        let people = [summary("Zoë de Vries", open: 2), summary("Anna", open: 0)]
        let result = UpcomingPlanner.matchPeople(attendeeNames: ["ZOE DE VRIES", "anna", "Bram"], people: people)
        XCTAssertEqual(result[0].personId, people[0].person.id)
        XCTAssertEqual(result[0].openCount, 2)
        XCTAssertEqual(result[1].personId, people[1].person.id)
        XCTAssertEqual(result[1].openCount, 0)
        XCTAssertNil(result[2].personId)
        XCTAssertEqual(result[2].openCount, 0)
        XCTAssertEqual(result.map(\.name), ["ZOE DE VRIES", "anna", "Bram"])
    }

    func testFirstNameOnlyDoesNotMatchAFullName() {
        let people = [summary("Anna de Vries", open: 3)]
        XCTAssertNil(UpcomingPlanner.matchPeople(attendeeNames: ["Anna"], people: people)[0].personId)
    }

    func testEmailAddressNeverMatches() {
        let people = [summary("anna@example.com", open: 1)]
        XCTAssertNil(UpcomingPlanner.matchPeople(attendeeNames: ["anna@example.com"], people: people)[0].personId)
    }

    func testBlankNameNeverMatches() {
        let people = [summary("Anna", open: 1)]
        XCTAssertNil(UpcomingPlanner.matchPeople(attendeeNames: ["  "], people: people)[0].personId)
    }
}
