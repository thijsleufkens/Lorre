import Foundation

/// An attendee of a meeting, matched against the saved people.
public struct AttendeeMatch: Sendable, Equatable {
    public var name: String
    public var personId: UUID?
    /// Open items with this person; 0 when there is no match.
    public var openCount: Int

    public init(name: String, personId: UUID?, openCount: Int) {
        self.name = name
        self.personId = personId
        self.openCount = openCount
    }
}

/// Pure choices about meetings: what is coming up, what is going on now, who is who.
public enum UpcomingPlanner {
    public static let horizon: TimeInterval = 24 * 3600
    public static let startTolerance: TimeInterval = 5 * 60

    /// Meetings that have not ended and start within the next 24 hours, by start, at most `limit`.
    public static func comingUp(meetings: [UpcomingMeeting], now: Date, limit: Int = 3) -> [UpcomingMeeting] {
        let until = now.addingTimeInterval(horizon)
        return meetings
            .filter { $0.end > now && $0.start <= until }
            .sorted { $0.start < $1.start }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// The meeting in progress, from 5 minutes before its start; the one that started last wins.
    public static func current(meetings: [UpcomingMeeting], now: Date) -> UpcomingMeeting? {
        meetings
            .filter { $0.start.addingTimeInterval(-startTolerance) <= now && now < $0.end }
            .max { $0.start < $1.start }
    }

    /// Matches attendee names to saved people on the full name, ignoring case and diacritics.
    /// A name that is an e-mail address never matches.
    public static func matchPeople(attendeeNames: [String], people: [PersonSummary]) -> [AttendeeMatch] {
        attendeeNames.map { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("@") else {
                return AttendeeMatch(name: name, personId: nil, openCount: 0)
            }
            let folded = PeopleStore.fold(trimmed)
            let match = people.first {
                PeopleStore.fold($0.person.name.trimmingCharacters(in: .whitespacesAndNewlines)) == folded
            }
            return AttendeeMatch(name: name, personId: match?.person.id, openCount: match?.openCount ?? 0)
        }
    }
}
