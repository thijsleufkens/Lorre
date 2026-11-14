import LorreCore
import XCTest
@testable import Lorre

final class FakeCalendarSource: CalendarSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _access: CalendarAccess
    private var _meetings: [UpcomingMeeting]
    private let grantsOnRequest: Bool
    private var _requestCount = 0

    init(access: CalendarAccess, meetings: [UpcomingMeeting] = [], grantsOnRequest: Bool = true) {
        _access = access
        _meetings = meetings
        self.grantsOnRequest = grantsOnRequest
    }

    var requestCount: Int { lock.withLock { _requestCount } }

    func access() -> CalendarAccess { lock.withLock { _access } }

    func requestAccess() async -> Bool {
        lock.withLock {
            _requestCount += 1
            _access = grantsOnRequest ? .granted : .denied
            return grantsOnRequest
        }
    }

    func meetings(from: Date, to: Date) async -> [UpcomingMeeting] {
        lock.withLock { _access == .granted ? _meetings : [] }
    }
}

@MainActor
final class ComingUpModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var database: LorreDatabase!

    override func setUpWithError() throws {
        database = try LorreDatabase.inMemory()
    }

    private func meeting(_ id: String, start: TimeInterval, names: [String] = []) -> UpcomingMeeting {
        UpcomingMeeting(
            eventId: id, title: "Overleg \(id)", start: now.addingTimeInterval(start),
            end: now.addingTimeInterval(start + 3600), attendeeNames: names
        )
    }

    private func model(_ source: FakeCalendarSource) -> ComingUpModel {
        ComingUpModel(source: source, database: database, now: { [now] in now })
    }

    /// A person with two approved open items.
    private func seedAnna() throws -> Person {
        let conversations = ConversationStore(database: database)
        let review = ReviewStore(database: database)
        let conversation = Conversation(title: "Eerder", state: .approved, startedAt: now.addingTimeInterval(-86_400))
        try conversations.save(conversation)
        let me = Participant(conversationId: conversation.id, name: "Ik", isUser: true)
        let other = Participant(conversationId: conversation.id, name: "Anna")
        try conversations.saveParticipants([me, other])
        let anna = try PeopleStore(database: database).createPerson(from: other.id)
        for text in ["Offerte", "Bellen"] {
            let outcome = try review.addOutcome(
                conversationId: conversation.id, kind: .openPoint, text: text,
                ownerParticipantId: nil, source: .model, now: now
            )
            _ = try review.setStatus(.approved, for: outcome.id, now: now)
        }
        return anna
    }

    func testNotAskedShowsNothingButOffersAccess() async {
        let source = FakeCalendarSource(access: .notAsked, meetings: [meeting("a", start: 600)])
        let model = model(source)
        await model.reload()
        XCTAssertEqual(model.calendarAccess, .notAsked)
        XCTAssertTrue(model.comingUp.isEmpty)
        XCTAssertEqual(source.requestCount, 0, "reloading never asks")
    }

    func testDeniedShowsNothing() async {
        let model = model(FakeCalendarSource(access: .denied, meetings: [meeting("a", start: 600)]))
        await model.reload()
        XCTAssertEqual(model.calendarAccess, .denied)
        XCTAssertTrue(model.comingUp.isEmpty)
    }

    func testGrantedListsMeetingsWithMatchedPeopleAndOpenCounts() async throws {
        let anna = try seedAnna()
        let source = FakeCalendarSource(
            access: .granted,
            meetings: [meeting("b", start: 7200, names: ["Bram"]), meeting("a", start: 600, names: ["Anna", "Bram"])]
        )
        let model = model(source)
        await model.reload()
        XCTAssertEqual(model.comingUp.map(\.id), ["a", "b"])
        let item = try XCTUnwrap(model.comingUp.first { $0.id == "a" })
        XCTAssertEqual(item.attendees.map(\.personId), [anna.id, nil])
        XCTAssertEqual(item.mostOpen?.openCount, 2)
        XCTAssertEqual(item.mostOpen?.name, "Anna")
        XCTAssertNil(model.comingUp.first { $0.id == "b" }?.mostOpen)
    }

    func testAllowCalendarAsksThenReloads() async {
        let source = FakeCalendarSource(access: .notAsked, meetings: [meeting("a", start: 600)])
        let model = model(source)
        await model.reload()
        XCTAssertTrue(model.comingUp.isEmpty)
        await model.allowCalendar()
        XCTAssertEqual(source.requestCount, 1)
        XCTAssertEqual(model.calendarAccess, .granted)
        XCTAssertEqual(model.comingUp.map(\.id), ["a"])
    }

    func testAllowCalendarRefusedEndsDenied() async {
        let model = model(FakeCalendarSource(access: .notAsked, grantsOnRequest: false))
        await model.allowCalendar()
        XCTAssertEqual(model.calendarAccess, .denied)
    }

    func testCurrentMeetingOnlyWithAccessAndLoadedMeetings() async {
        let denied = model(FakeCalendarSource(access: .denied, meetings: [meeting("now", start: -60)]))
        await denied.reload()
        XCTAssertNil(denied.currentMeeting())

        let granted = model(FakeCalendarSource(access: .granted, meetings: [meeting("now", start: -60)]))
        XCTAssertNil(granted.currentMeeting(), "nothing is loaded yet")
        await granted.reload()
        XCTAssertEqual(granted.currentMeeting()?.eventId, "now")
    }
}
