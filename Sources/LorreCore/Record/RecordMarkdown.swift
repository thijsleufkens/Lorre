import Foundation

/// The readable version of a record, for people without an agent.
public enum RecordMarkdown {
    public static func render(
        _ record: MeetingRecord,
        language: LorreLanguage = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let dutch = language == .dutch
        let names = Dictionary(uniqueKeysWithValues: record.conversation.participants.map { ($0.id, $0.name) })
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: dutch ? "nl_NL" : "en_GB")
        formatter.timeZone = timeZone
        formatter.dateFormat = dutch ? "d MMMM yyyy 'om' HH:mm" : "d MMMM yyyy 'at' HH:mm"
        let dayFormatter = DateFormatter()
        dayFormatter.locale = formatter.locale
        dayFormatter.timeZone = timeZone
        dayFormatter.dateFormat = "d MMMM yyyy"

        var lines = ["# \(record.conversation.title)", ""]
        var facts = [formatter.string(from: record.conversation.startedAt)]
        if let duration = record.conversation.durationSeconds {
            facts.append("\(max(1, Int((duration / 60).rounded()))) min")
        }
        facts.append(record.conversation.type.title(language))
        lines.append(facts.joined(separator: " · "))
        let people = record.conversation.participants.map(\.name)
        if !people.isEmpty {
            lines.append((dutch ? "Deelnemers: " : "Participants: ") + people.joined(separator: ", "))
        }
        lines.append("")

        if record.status == .draft {
            lines += [
                dutch
                    ? "_Concept: dit gesprek is nog niet nagekeken, dus er staan nog geen uitkomsten in._"
                    : "_Draft: this conversation has not been reviewed yet, so it has no outcomes._",
                "",
            ]
        }

        for kind in OutcomeKind.displayOrder {
            let items = record.outcomes.filter { $0.kind == kind }
            guard !items.isEmpty else { continue }
            lines += ["## \(kind.title(language))", ""]
            for item in items {
                var line = kind.hasOwner ? "- [ ] \(item.text)" : "- \(item.text)"
                var details: [String] = []
                if let owner = item.ownerId.flatMap({ names[$0] }) { details.append(owner) }
                if let due = item.due {
                    details.append((dutch ? "vóór " : "by ") + dayFormatter.string(from: due))
                }
                if let start = item.evidence.startMs { details.append(timestamp(start)) }
                if !details.isEmpty { line += " — " + details.joined(separator: ", ") }
                lines.append(line)
            }
            lines.append("")
        }

        lines += ["## Transcript", ""]
        // One paragraph per turn: consecutive segments of the same speaker are joined.
        var paragraphs: [String] = []
        var previousSpeaker: UUID?
        var hasPrevious = false
        for segment in record.transcript.segments {
            if hasPrevious, previousSpeaker == segment.participantId {
                paragraphs[paragraphs.count - 1] += " " + segment.text
            } else {
                let speaker = segment.participantId.flatMap { names[$0] } ?? "?"
                paragraphs.append("**\(speaker)** (\(timestamp(segment.startMs))): \(segment.text)")
            }
            previousSpeaker = segment.participantId
            hasPrevious = true
        }
        lines.append(paragraphs.joined(separator: "\n\n"))
        return lines.joined(separator: "\n") + "\n"
    }

    static func timestamp(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1000)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
