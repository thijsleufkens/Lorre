import Foundation
import LorreCore

/// Pure text helpers for the screens, kept out of the views so they can be tested.
enum ViewFormat {
    // MARK: Durations and clocks

    /// "29 min", "1 u 5 min"; nil when the duration is unknown.
    static func duration(_ seconds: Double?, _ strings: Strings) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        if seconds < 30 { return strings.lessThanAMinute }
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) \(strings.minuteUnit)" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0
            ? "\(hours) \(strings.hourUnit)"
            : "\(hours) \(strings.hourUnit) \(rest) \(strings.minuteUnit)"
    }

    /// "21:26", or "1:02:03" past an hour.
    static func clock(milliseconds: Int) -> String {
        clock(seconds: max(0, milliseconds) / 1000)
    }

    static func clock(seconds total: Int) -> String {
        let total = max(0, total)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: Dates

    /// "vandaag 10:00", "gisteren 10:00", "8 okt 10:00", or with the year when it is another year.
    static func dayAndTime(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current, _ strings: Strings
    ) -> String {
        let time = formatted(date, template: "HH:mm", calendar: calendar, strings)
        if calendar.isDate(date, inSameDayAs: now) { return "\(strings.todayWord) \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "\(strings.yesterdayWord) \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "\(strings.tomorrowWord) \(time)"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = formatted(date, template: sameYear ? "d MMM" : "d MMM y", calendar: calendar, strings)
        return "\(day) \(time)"
    }

    /// "8 okt" or "8 Oct 2025", without a time; used where only the day matters.
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current, _ strings: Strings) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return formatted(date, template: sameYear ? "d MMM" : "d MMM y", calendar: calendar, strings)
    }

    private static func formatted(_ date: Date, template: String, calendar: Calendar, _ strings: Strings) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: strings.language.rawValue)
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    // MARK: States

    /// The state of a conversation in words for the user.
    static func stateLabel(_ conversation: Conversation, _ strings: Strings) -> String {
        switch conversation.state {
        case .recording: strings.stateRecording
        case .interrupted: strings.stateInterrupted
        case .processing: conversation.lastError == nil ? strings.stateProcessing : strings.stateFailed
        case .proposed: strings.stateToReview
        case .approved: strings.stateDone
        case .changed: strings.stateChanged
        }
    }

    // MARK: Errors and retry

    /// The kinds of trouble Lorre can explain in plain words.
    enum ErrorKind: Equatable {
        case noSpeech, silentMicrophone, interrupted, recovered, missingFile, other
    }

    /// Recognises the raw messages written by the recorder and the processing code. The raw text is
    /// English and technical; it is only ever matched here, never shown.
    static func errorKind(_ raw: String) -> ErrorKind {
        let text = raw.lowercased()
        func has(_ parts: String...) -> Bool { parts.contains { text.contains($0) } }

        if has("recovered") && has("being transcribed") { return .recovered }
        if has("not receiving any sound from the microphone", "own voice was not recorded",
               "microphone access is required") {
            return .silentMicrophone
        }
        if has("no speech") { return .noSpeech }
        if has("interrupted before it was stopped", "found on disk without a conversation") {
            return .interrupted
        }
        if has("no audio to transcribe", "no audio was captured", "recorded audio was not captured",
               "could not be written", "could not write", "could not load recorded audio",
               "stems are incomplete", "no such file", "file is missing", "does not exist") {
            return .missingFile
        }
        return .other
    }

    /// One calm sentence with what to do next for a raw error message; nil when there is no message.
    /// Unknown messages get a generic sentence, the raw text is never part of the result.
    static func friendlyError(_ raw: String?, strings: Strings) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch errorKind(raw) {
        case .noSpeech: return strings.errorNoSpeech
        case .silentMicrophone: return strings.errorSilentMicrophone
        case .interrupted: return strings.errorInterrupted
        case .recovered: return strings.errorRecovered
        case .missingFile: return strings.errorMissingFile
        case .other: return strings.errorGeneric
        }
    }

    /// Whether the user can ask for processing again: an interrupted recording, or a failed run.
    static func isRetryable(_ conversation: Conversation) -> Bool {
        conversation.state == .interrupted || (conversation.state == .processing && conversation.lastError != nil)
    }

    /// The state text of a conversation in progress; while it is queued or running it says it is being
    /// written out, whatever an earlier failure left behind.
    static func progressLabel(_ conversation: Conversation, isQueuedOrRunning: Bool, _ strings: Strings) -> String {
        isQueuedOrRunning ? strings.stateProcessing : stateLabel(conversation, strings)
    }

    /// Whether there is a transcript to review.
    static func isReviewable(_ conversation: Conversation) -> Bool {
        switch conversation.state {
        case .proposed, .approved, .changed: true
        case .recording, .interrupted, .processing: false
        }
    }

    // MARK: Grouping

    struct MonthGroup: Identifiable, Equatable {
        var id: Date
        var title: String
        var items: [ConversationSummary]
    }

    /// Groups a list that is already sorted newest first by the month of each conversation, keeping the order.
    static func monthGroups(
        _ items: [ConversationSummary], calendar: Calendar = .current, _ strings: Strings
    ) -> [MonthGroup] {
        var groups: [MonthGroup] = []
        for item in items {
            let start = calendar.dateInterval(of: .month, for: item.conversation.startedAt)?.start
                ?? item.conversation.startedAt
            if let last = groups.indices.last, groups[last].id == start {
                groups[last].items.append(item)
            } else {
                let title = formatted(start, template: "MMMM y", calendar: calendar, strings)
                groups.append(MonthGroup(id: start, title: String(title.prefix(1).uppercased() + title.dropFirst()), items: [item]))
            }
        }
        return groups
    }

    // MARK: Search snippets

    struct SnippetPiece: Equatable {
        var text: String
        var isMatch: Bool
    }

    /// Splits a search snippet that marks matches with `[` and `]` into plain and matched pieces.
    static func snippetPieces(_ snippet: String) -> [SnippetPiece] {
        var pieces: [SnippetPiece] = []
        var current = ""
        var matching = false
        func flush() {
            if !current.isEmpty { pieces.append(SnippetPiece(text: current, isMatch: matching)) }
            current = ""
        }
        for character in snippet {
            switch character {
            case "[":
                flush()
                matching = true
            case "]":
                flush()
                matching = false
            default:
                current.append(character)
            }
        }
        flush()
        return pieces
    }

    // MARK: Transcript selection

    /// The first sentence of `text`, whitespace collapsed, cut at `maxLength` characters on a word boundary.
    static func firstSentence(of text: String, maxLength: Int = 200) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var result = collapsed
        let characters = Array(collapsed)
        for index in characters.indices where ".?!".contains(characters[index]) {
            let next = index + 1
            if next == characters.count || characters[next] == " " {
                result = String(characters[...index])
                break
            }
        }
        guard result.count > maxLength else { return result }
        let cut = String(result.prefix(maxLength))
        let trimmed = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
        return trimmed + "…"
    }

    /// The selection after a click on `target`: a plain click toggles it, a shift-click extends from `anchor`.
    static func selection(
        after target: UUID, order: [UUID], anchor: UUID?, current: Set<UUID>, extend: Bool
    ) -> Set<UUID> {
        if extend, let anchor,
           let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: target) {
            return current.union(order[min(from, to)...max(from, to)])
        }
        var next = current
        if next.contains(target) { next.remove(target) } else { next.insert(target) }
        return next
    }
}
