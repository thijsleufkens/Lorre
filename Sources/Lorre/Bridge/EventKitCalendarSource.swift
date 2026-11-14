import EventKit
import Foundation
import LorreCore

/// The calendar on this Mac through EventKit. The only file that imports it.
final class EventKitCalendarSource: CalendarSource, @unchecked Sendable {
    // EKEventStore is documented as usable from any thread; it is created lazily so that
    // nothing touches the calendar before the user has asked for it.
    private let lock = NSLock()
    private var cachedStore: EKEventStore?

    init() {}

    private var store: EKEventStore {
        lock.withLock {
            if let cachedStore { return cachedStore }
            let created = EKEventStore()
            cachedStore = created
            return created
        }
    }

    func access() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func meetings(from: Date, to: Date) async -> [UpcomingMeeting] {
        guard access() == .granted else { return [] }
        let store = self.store
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { event in
                // Skip what the user declined.
                !(event.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined }
            }
            .map { event in
                UpcomingMeeting(
                    eventId: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    attendeeNames: (event.attendees ?? [])
                        .filter { !$0.isCurrentUser }
                        .compactMap { $0.name }
                )
            }
            .sorted { $0.start < $1.start }
    }
}
