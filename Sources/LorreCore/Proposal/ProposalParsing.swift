import Foundation

/// Tolerant reading of what a small model says: code fences, prose around the JSON, unknown fields.
enum ProposalParsing {
    /// The outermost JSON value in the text, or nil when there is none that parses.
    static func jsonValue(in raw: String) -> Any? {
        let text = stripFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = parse(text) { return value }
        let opens: [(Character, Character)] = [("{", "}"), ("[", "]")]
        var attempts: [(start: String.Index, end: String.Index)] = []
        for (open, close) in opens {
            if let start = text.firstIndex(of: open), let end = text.lastIndex(of: close), start < end {
                attempts.append((start, end))
            }
        }
        for attempt in attempts.sorted(by: { $0.start < $1.start }) {
            if let value = parse(String(text[attempt.start...attempt.end])) { return value }
        }
        return nil
    }

    private static func parse(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func stripFences(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .joined(separator: "\n")
    }

    /// The list of items inside a parsed answer: a bare array, or the first array in an object.
    /// Returns nil when the answer has no list at all (as opposed to an empty one).
    static func items(from value: Any?) -> [[String: Any]]? {
        if let array = value as? [Any] { return array.compactMap { $0 as? [String: Any] } }
        guard let object = value as? [String: Any] else { return nil }
        for key in ["items", "outcomes", "candidates", "uitkomsten", "kandidaten"] {
            if let array = object[key] as? [Any] { return array.compactMap { $0 as? [String: Any] } }
        }
        if let array = object.values.compactMap({ $0 as? [Any] }).first {
            return array.compactMap { $0 as? [String: Any] }
        }
        if object["kind"] != nil { return [object] }
        return nil
    }

    static func string(_ item: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let text = item[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    static func kind(_ item: [String: Any]) -> OutcomeKind? {
        guard let text = string(item, ["kind", "type"]) else { return nil }
        let folded = text.lowercased()
        return OutcomeKind.allCases.first { $0.rawValue.lowercased() == folded }
    }

    /// Whole numbers from an array whose entries may be numbers or numeric strings.
    static func numbers(_ item: [String: Any], _ keys: [String]) -> [Int] {
        for key in keys {
            guard let raw = item[key] else { continue }
            let entries: [Any] = (raw as? [Any]) ?? [raw]
            var result: [Int] = []
            for entry in entries {
                if let int = entry as? Int { result.append(int) }
                else if let double = entry as? Double, double == double.rounded() { result.append(Int(double)) }
                else if let text = entry as? String, let int = Int(text.trimmingCharacters(in: .whitespaces)) { result.append(int) }
            }
            return result
        }
        return []
    }

    /// The owner field: nil when absent, `.some(nil)` when explicitly null or empty.
    static func ownerName(_ item: [String: Any]) -> String?? {
        for key in ["owner", "eigenaar"] where item[key] != nil {
            if let text = item[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let empty = trimmed.isEmpty || ["null", "none", "nil", "-", "n/a"].contains(trimmed.lowercased())
                return .some(empty ? nil : trimmed)
            }
            return .some(nil)
        }
        return nil
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Maps the name a model gives to a participant of the conversation.
struct ParticipantMatcher {
    static let userAliases: Set<String> = ["ik", "me", "mij", "i", "myself", "ikzelf", "user", "gebruiker", "de gebruiker"]

    let participants: [Participant]

    func match(_ name: String?) -> UUID? {
        guard let name else { return nil }
        let wanted = ProposalParsing.fold(name)
        guard !wanted.isEmpty else { return nil }
        if Self.userAliases.contains(wanted) {
            return participants.first(where: \.isUser)?.id
        }
        if let exact = participants.first(where: { ProposalParsing.fold($0.name) == wanted }) { return exact.id }
        // A first name is enough, as long as it points at one person.
        let byFirstName = participants.filter { ProposalParsing.fold($0.name).split(separator: " ").first.map(String.init) == wanted }
        if byFirstName.count == 1 { return byFirstName[0].id }
        return nil
    }
}
