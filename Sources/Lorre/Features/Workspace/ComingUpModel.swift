import Foundation
import LorreCore
import Observation

/// One meeting that is coming up, with the people in it that Lorre already knows.
struct ComingUpItem: Identifiable, Equatable {
    var meeting: UpcomingMeeting
    var attendees: [AttendeeMatch]
    var id: String { meeting.eventId }

    /// The matched person with the most open items, when any have open items.
    var mostOpen: AttendeeMatch? {
        attendees.filter { $0.personId != nil && $0.openCount > 0 }.max { $0.openCount < $1.openCount }
    }
}

/// What the calendar says is coming up, for the Today screen and for naming a new recording.
@MainActor
@Observable
final class ComingUpModel {
    private(set) var calendarAccess: CalendarAccess
    private(set) var comingUp: [ComingUpItem] = []
    /// Everything loaded at the last reload; the recorder looks here and never waits on the calendar.
    @ObservationIgnored private var loaded: [UpcomingMeeting] = []

    @ObservationIgnored private let source: any CalendarSource
    @ObservationIgnored private let database: LorreDatabase
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var reloadToken = 0

    init(source: any CalendarSource, database: LorreDatabase, now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.database = database
        self.now = now
        self.calendarAccess = source.access()
    }

    /// Reads the calendar again. Without access nothing is shown and nothing is read.
    func reload() async {
        reloadToken += 1
        let token = reloadToken
        let access = source.access()
        calendarAccess = access
        guard access == .granted else {
            loaded = []
            comingUp = []
            return
        }
        let current = now()
        let fetched = await source.meetings(from: current, to: current.addingTimeInterval(UpcomingPlanner.horizon))
        guard token == reloadToken else { return }
        loaded = fetched
        let upcoming = UpcomingPlanner.comingUp(meetings: fetched, now: current)
        let people = (try? PeopleStore(database: database).people()) ?? []
        comingUp = upcoming.map {
            ComingUpItem(
                meeting: $0,
                attendees: UpcomingPlanner.matchPeople(attendeeNames: $0.attendeeNames, people: people)
            )
        }
    }

    /// Asks for access (the only place that does), then reloads.
    func allowCalendar() async {
        _ = await source.requestAccess()
        await reload()
    }

    /// The meeting in progress according to what is loaded. Only when access is already granted.
    func currentMeeting() -> UpcomingMeeting? {
        guard calendarAccess == .granted else { return nil }
        return UpcomingPlanner.current(meetings: loaded, now: now())
    }
}
