import Foundation

/// A meeting from the user's calendar, reduced to what Lorre shows and uses.
public struct UpcomingMeeting: Sendable, Equatable, Identifiable {
    public var eventId: String
    public var title: String
    public var start: Date
    public var end: Date
    /// The other people only, never the user.
    public var attendeeNames: [String]
    public var id: String { eventId }

    public init(eventId: String, title: String, start: Date, end: Date, attendeeNames: [String] = []) {
        self.eventId = eventId
        self.title = title
        self.start = start
        self.end = end
        self.attendeeNames = attendeeNames
    }
}

public enum CalendarAccess: Sendable, Equatable {
    case notAsked, granted, denied
}

/// Where meetings come from. The app target implements it with EventKit; tests use a fake.
public protocol CalendarSource: Sendable {
    func access() -> CalendarAccess
    /// Asks the user for access; true when it is granted.
    func requestAccess() async -> Bool
    /// Meetings that overlap the period, sorted by start. Empty without access. No all-day events.
    func meetings(from: Date, to: Date) async -> [UpcomingMeeting]
}

/// A source for when no calendar is available: access is denied, so nothing is shown.
public struct NoCalendarSource: CalendarSource {
    public init() {}
    public func access() -> CalendarAccess { .denied }
    public func requestAccess() async -> Bool { false }
    public func meetings(from: Date, to: Date) async -> [UpcomingMeeting] { [] }
}
