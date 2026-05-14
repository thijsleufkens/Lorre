import Foundation

enum SessionDateGroup: Hashable {
    case today
    case yesterday
    case thisWeek
    case earlier
}

struct SessionDateGrouper {
    struct Bucket {
        let group: SessionDateGroup
        let sessions: [SessionManifest]
    }

    let calendar: Calendar
    let now: Date

    func group(_ sessions: [SessionManifest]) -> [Bucket] {
        var today: [SessionManifest] = []
        var yesterday: [SessionManifest] = []
        var thisWeek: [SessionManifest] = []
        var earlier: [SessionManifest] = []

        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfWeekWindow = calendar.date(byAdding: .day, value: -6, to: startOfToday)!

        for session in sessions {
            let recorded = session.recordedAt ?? session.updatedAt
            let startOfRecorded = calendar.startOfDay(for: recorded)
            if startOfRecorded >= startOfToday {
                today.append(session)
            } else if startOfRecorded >= startOfYesterday {
                yesterday.append(session)
            } else if startOfRecorded >= startOfWeekWindow {
                thisWeek.append(session)
            } else {
                earlier.append(session)
            }
        }

        var result: [Bucket] = []
        if !today.isEmpty { result.append(.init(group: .today, sessions: today)) }
        if !yesterday.isEmpty { result.append(.init(group: .yesterday, sessions: yesterday)) }
        if !thisWeek.isEmpty { result.append(.init(group: .thisWeek, sessions: thisWeek)) }
        if !earlier.isEmpty { result.append(.init(group: .earlier, sessions: earlier)) }
        return result
    }
}
