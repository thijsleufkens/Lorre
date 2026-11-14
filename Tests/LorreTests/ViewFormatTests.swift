import LorreCore
import XCTest
@testable import Lorre

final class ViewFormatTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func summary(_ startedAt: Date, state: ConversationState = .proposed) -> ConversationSummary {
        ConversationSummary(
            conversation: Conversation(title: "t", state: state, startedAt: startedAt),
            participantNames: [], segmentCount: 0, proposedOutcomes: 0, approvedOutcomes: 0
        )
    }

    func testDuration() {
        let nl = Strings.dutch
        XCTAssertNil(ViewFormat.duration(nil, nl))
        XCTAssertEqual(ViewFormat.duration(10, nl), "< 1 min")
        XCTAssertEqual(ViewFormat.duration(29 * 60, nl), "29 min")
        XCTAssertEqual(ViewFormat.duration(60 * 60, nl), "1 u")
        XCTAssertEqual(ViewFormat.duration(65 * 60, nl), "1 u 5 min")
        XCTAssertEqual(ViewFormat.duration(65 * 60, .english), "1 h 5 min")
    }

    func testClock() {
        XCTAssertEqual(ViewFormat.clock(milliseconds: 0), "0:00")
        XCTAssertEqual(ViewFormat.clock(milliseconds: 1_286_000), "21:26")
        XCTAssertEqual(ViewFormat.clock(seconds: 3723), "1:02:03")
        XCTAssertEqual(ViewFormat.clock(seconds: -5), "0:00")
    }

    func testDayAndTime() {
        let now = date(2026, 11, 14, 15)
        let nl = Strings.dutch
        XCTAssertEqual(ViewFormat.dayAndTime(date(2026, 11, 14, 10), now: now, calendar: calendar, nl), "vandaag 10:00")
        XCTAssertEqual(ViewFormat.dayAndTime(date(2026, 11, 13, 9, 5), now: now, calendar: calendar, nl), "gisteren 09:05")
        let older = ViewFormat.dayAndTime(date(2026, 10, 8, 10), now: now, calendar: calendar, nl)
        XCTAssertTrue(older.hasPrefix("8 okt"), older)
        XCTAssertTrue(older.hasSuffix("10:00"), older)
        let otherYear = ViewFormat.dayAndTime(date(2025, 10, 8, 10), now: now, calendar: calendar, nl)
        XCTAssertTrue(otherYear.contains("2025"), otherYear)
    }

    func testMonthGroupsKeepOrderAndSplitOnMonth() {
        let items = [
            summary(date(2026, 11, 10)), summary(date(2026, 11, 2)),
            summary(date(2026, 10, 8)), summary(date(2025, 11, 3)),
        ]
        let groups = ViewFormat.monthGroups(items, calendar: calendar, .dutch)
        XCTAssertEqual(groups.map(\.items.count), [2, 1, 1])
        XCTAssertEqual(groups[0].title, "November 2026")
        XCTAssertEqual(groups[1].title, "Oktober 2026")
        XCTAssertEqual(groups[2].title, "November 2025")
        XCTAssertTrue(ViewFormat.monthGroups([], calendar: calendar, .dutch).isEmpty)
    }

    func testSnippetPieces() {
        XCTAssertEqual(
            ViewFormat.snippetPieces("de [prijs] is [hoog] nu"),
            [
                .init(text: "de ", isMatch: false), .init(text: "prijs", isMatch: true),
                .init(text: " is ", isMatch: false), .init(text: "hoog", isMatch: true),
                .init(text: " nu", isMatch: false),
            ]
        )
        XCTAssertEqual(ViewFormat.snippetPieces("zonder"), [.init(text: "zonder", isMatch: false)])
        XCTAssertEqual(ViewFormat.snippetPieces("[hele]"), [.init(text: "hele", isMatch: true)])
        XCTAssertTrue(ViewFormat.snippetPieces("").isEmpty)
        // An unclosed bracket does not lose text.
        XCTAssertEqual(ViewFormat.snippetPieces("a [b"), [.init(text: "a ", isMatch: false), .init(text: "b", isMatch: true)])
    }

    func testFirstSentence() {
        XCTAssertEqual(ViewFormat.firstSentence(of: "Dat doen we. Daarna bellen we."), "Dat doen we.")
        XCTAssertEqual(ViewFormat.firstSentence(of: "Wanneer dan? Morgen."), "Wanneer dan?")
        XCTAssertEqual(ViewFormat.firstSentence(of: "  geen punt\n hier  "), "geen punt hier")
        XCTAssertEqual(ViewFormat.firstSentence(of: "Versie 2.5 is klaar"), "Versie 2.5 is klaar")
        XCTAssertEqual(ViewFormat.firstSentence(of: ""), "")
        let long = String(repeating: "woord ", count: 100)
        let cut = ViewFormat.firstSentence(of: long, maxLength: 20)
        XCTAssertTrue(cut.hasSuffix("…"))
        XCTAssertLessThanOrEqual(cut.count, 21)
    }

    func testSelectionToggleAndRange() {
        let ids = (0..<5).map { _ in UUID() }
        var selection = ViewFormat.selection(after: ids[1], order: ids, anchor: nil, current: [], extend: false)
        XCTAssertEqual(selection, [ids[1]])
        selection = ViewFormat.selection(after: ids[1], order: ids, anchor: ids[1], current: selection, extend: false)
        XCTAssertTrue(selection.isEmpty, "a second click deselects")
        selection = ViewFormat.selection(after: ids[1], order: ids, anchor: nil, current: [], extend: false)
        selection = ViewFormat.selection(after: ids[3], order: ids, anchor: ids[1], current: selection, extend: true)
        XCTAssertEqual(selection, Set(ids[1...3]))
        // Extending backwards works too, and without an anchor it behaves like a plain click.
        let backwards = ViewFormat.selection(after: ids[0], order: ids, anchor: ids[2], current: [], extend: true)
        XCTAssertEqual(backwards, Set(ids[0...2]))
        let noAnchor = ViewFormat.selection(after: ids[4], order: ids, anchor: nil, current: [], extend: true)
        XCTAssertEqual(noAnchor, [ids[4]])
    }

    func testStateLabelsAndReviewability() {
        let nl = Strings.dutch
        var conversation = Conversation(title: "t", state: .processing, startedAt: Date())
        XCTAssertEqual(ViewFormat.stateLabel(conversation, nl), nl.stateProcessing)
        conversation.lastError = "kapot"
        XCTAssertEqual(ViewFormat.stateLabel(conversation, nl), nl.stateFailed)
        XCTAssertFalse(ViewFormat.isReviewable(conversation))
        for state in ConversationState.allCases {
            conversation.state = state
            XCTAssertFalse(ViewFormat.stateLabel(conversation, nl).isEmpty)
        }
        for state in [ConversationState.proposed, .approved, .changed] {
            conversation.state = state
            XCTAssertTrue(ViewFormat.isReviewable(conversation))
        }
    }
}
