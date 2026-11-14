import Foundation
import GRDB

/// A person in the list of people: who they are and how much is open with them.
public struct PersonSummary: Identifiable, Equatable, Sendable {
    public var person: Person
    public var conversationCount: Int
    public var lastConversationAt: Date?
    /// Approved outcomes of kind myAction, theirCommitment, openPoint and followUpHook in their conversations.
    public var openCount: Int
    public var id: UUID { person.id }

    public init(person: Person, conversationCount: Int, lastConversationAt: Date?, openCount: Int) {
        self.person = person
        self.conversationCount = conversationCount
        self.lastConversationAt = lastConversationAt
        self.openCount = openCount
    }
}

/// One page per person: what was agreed, what is still open, what to come back to.
/// Only approved outcomes ever appear here.
public struct PersonBrief: Equatable, Sendable {
    public struct Item: Identifiable, Equatable, Sendable {
        public var outcome: Outcome
        public var conversation: Conversation
        public var ownerName: String?
        public var id: UUID { outcome.id }

        public init(outcome: Outcome, conversation: Conversation, ownerName: String?) {
            self.outcome = outcome
            self.conversation = conversation
            self.ownerName = ownerName
        }
    }

    public var person: Person
    /// Newest first.
    public var conversations: [Conversation]
    /// Approved, owned by the user.
    public var myActions: [Item]
    /// Approved, owned by this person.
    public var theirCommitments: [Item]
    public var openPoints: [Item]
    /// Outcomes of kind followUpHook.
    public var hooks: [Item]
    /// Outcomes of kind personNote.
    public var notes: [Item]
    /// Decisions of the most recent conversation only.
    public var lastDecisions: [Item]

    public init(
        person: Person, conversations: [Conversation],
        myActions: [Item], theirCommitments: [Item], openPoints: [Item],
        hooks: [Item], notes: [Item], lastDecisions: [Item]
    ) {
        self.person = person
        self.conversations = conversations
        self.myActions = myActions
        self.theirCommitments = theirCommitments
        self.openPoints = openPoints
        self.hooks = hooks
        self.notes = notes
        self.lastDecisions = lastDecisions
    }
}

public struct PeopleStore: Sendable {
    public enum PeopleError: Error, Equatable, LocalizedError {
        case personNotFound
        case participantNotFound
        /// The user is never a person in their own list.
        case userCannotBePerson
        case blankName
        case cannotMergeWithItself

        /// Plain-language text in the user's language, for showing in the screens.
        public var errorDescription: String? {
            let dutch = LorreLanguage.current == .dutch
            switch self {
            case .personNotFound:
                return dutch ? "Deze persoon bestaat niet meer." : "This person no longer exists."
            case .participantNotFound:
                return dutch ? "Deze deelnemer bestaat niet meer in dit gesprek." : "This participant is no longer in this conversation."
            case .userCannotBePerson:
                return dutch ? "Jij zelf staat niet in je lijst met mensen." : "You are not part of your own list of people."
            case .blankName:
                return dutch ? "Een persoon heeft een naam nodig." : "A person needs a name."
            case .cannotMergeWithItself:
                return dutch ? "Kies een andere persoon om mee samen te voegen." : "Choose another person to merge with."
            }
        }
    }

    let database: LorreDatabase

    public init(database: LorreDatabase) {
        self.database = database
    }

    private static let openKinds: [OutcomeKind] = [.myAction, .theirCommitment, .openPoint, .followUpHook]

    // MARK: Reading

    /// People by their last conversation, newest first (people without one last, by name).
    /// Searches name, organisation and role, ignoring case and diacritics.
    public func people(matching search: String = "") throws -> [PersonSummary] {
        let query = Self.fold(search)
        return try database.queue.read { db in
            var persons = try Person.fetchAll(db)
            if !query.isEmpty {
                persons = persons.filter { person in
                    [person.name, person.organisation, person.role].contains { value in
                        value.map { Self.fold($0).contains(query) } ?? false
                    }
                }
            }
            var conversationCount: [UUID: Int] = [:]
            var lastAt: [UUID: Date] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT p.personId AS personId, c.id AS conversationId, c.startedAt AS startedAt
                  FROM participant p JOIN conversation c ON c.id = p.conversationId
                 WHERE p.personId IS NOT NULL AND p.isUser = 0
                """)
            for row in rows {
                guard let personId = UUID(uuidString: row["personId"] as String) else { continue }
                let startedAt: Date = row["startedAt"]
                conversationCount[personId, default: 0] += 1
                lastAt[personId] = max(lastAt[personId] ?? .distantPast, startedAt)
            }
            let kinds = Self.openKinds.map { "'\($0.rawValue)'" }.joined(separator: ", ")
            var openCount: [UUID: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT pp.personId AS personId, COUNT(*) AS n
                  FROM outcome o
                  JOIN (SELECT DISTINCT personId, conversationId FROM participant
                         WHERE personId IS NOT NULL AND isUser = 0) pp ON pp.conversationId = o.conversationId
                 WHERE o.status = 'approved' AND o.kind IN (\(kinds))
                 GROUP BY pp.personId
                """) {
                if let id = UUID(uuidString: row["personId"] as String) { openCount[id] = row["n"] }
            }
            let summaries = persons.map {
                PersonSummary(
                    person: $0,
                    conversationCount: conversationCount[$0.id] ?? 0,
                    lastConversationAt: lastAt[$0.id],
                    openCount: openCount[$0.id] ?? 0
                )
            }
            return summaries.sorted { a, b in
                switch (a.lastConversationAt, b.lastConversationAt) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    let order = a.person.name.localizedCaseInsensitiveCompare(b.person.name)
                    return order == .orderedSame ? a.id.uuidString < b.id.uuidString : order == .orderedAscending
                }
            }
        }
    }

    public func brief(_ personId: UUID) throws -> PersonBrief? {
        try database.queue.read { db in try Self.brief(db, personId: personId) }
    }

    /// Briefs of the people whose name equals one of the given names (ignoring case and diacritics),
    /// for preparing an upcoming meeting. Ordered by name.
    public func brief(forUpcoming names: [String]) throws -> [PersonBrief] {
        let wanted = Set(names.map(Self.fold).filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return [] }
        return try database.queue.read { db in
            let matches = try Person.fetchAll(db)
                .filter { wanted.contains(Self.fold($0.name)) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return try matches.compactMap { try Self.brief(db, personId: $0.id) }
        }
    }

    private static func brief(_ db: Database, personId: UUID) throws -> PersonBrief? {
        guard let person = try Person.fetchOne(db, key: personId.uuidString) else { return nil }
        let conversations = try Conversation.fetchAll(db, sql: """
            SELECT * FROM conversation
             WHERE id IN (SELECT conversationId FROM participant WHERE personId = ? AND isUser = 0)
             ORDER BY startedAt DESC, id
            """, arguments: [personId.uuidString])
        let byId = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        let participants = try Participant.fetchAll(db, sql: """
            SELECT * FROM participant
             WHERE conversationId IN (SELECT conversationId FROM participant WHERE personId = ? AND isUser = 0)
            """, arguments: [personId.uuidString])
        let participantById = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })
        let outcomes = try Outcome.fetchAll(db, sql: """
            SELECT * FROM outcome
             WHERE status = 'approved'
               AND conversationId IN (SELECT conversationId FROM participant WHERE personId = ? AND isUser = 0)
            """, arguments: [personId.uuidString])

        var items: [PersonBrief.Item] = outcomes.compactMap { outcome in
            guard let conversation = byId[outcome.conversationId] else { return nil }
            let owner = outcome.ownerParticipantId.flatMap { participantById[$0] }
            return PersonBrief.Item(outcome: outcome, conversation: conversation, ownerName: owner?.name)
        }
        items.sort { a, b in
            if a.conversation.startedAt != b.conversation.startedAt {
                return a.conversation.startedAt > b.conversation.startedAt
            }
            let (x, y) = (a.outcome.evidenceStartMs ?? .max, b.outcome.evidenceStartMs ?? .max)
            if x != y { return x < y }
            if a.outcome.createdAt != b.outcome.createdAt { return a.outcome.createdAt < b.outcome.createdAt }
            return a.id.uuidString < b.id.uuidString
        }

        // An owner that is missing counts for both sides: the conversation is with this person.
        func ownerBelongsToPerson(_ item: PersonBrief.Item) -> Bool {
            guard let id = item.outcome.ownerParticipantId else { return true }
            return participantById[id]?.personId == personId
        }
        func ownerIsUser(_ item: PersonBrief.Item) -> Bool {
            guard let id = item.outcome.ownerParticipantId else { return true }
            return participantById[id]?.isUser ?? false
        }
        func of(_ kind: OutcomeKind) -> [PersonBrief.Item] { items.filter { $0.outcome.kind == kind } }

        let newest = conversations.first?.id
        return PersonBrief(
            person: person,
            conversations: conversations,
            myActions: of(.myAction).filter(ownerIsUser),
            theirCommitments: of(.theirCommitment).filter(ownerBelongsToPerson),
            openPoints: of(.openPoint),
            hooks: of(.followUpHook),
            notes: of(.personNote),
            lastDecisions: of(.decision).filter { $0.conversation.id == newest }
        )
    }

    // MARK: Linking

    @discardableResult
    public func link(participant: UUID, toPerson personId: UUID) throws -> Person {
        try database.queue.write { db in
            var participant = try Self.nonUserParticipant(db, participant)
            guard let person = try Person.fetchOne(db, key: personId.uuidString) else {
                throw PeopleError.personNotFound
            }
            participant.personId = person.id
            try participant.update(db)
            return person
        }
    }

    /// Makes a new person from the participant's name and links it.
    @discardableResult
    public func createPerson(from participantId: UUID) throws -> Person {
        try database.queue.write { db in
            var participant = try Self.nonUserParticipant(db, participantId)
            let name = participant.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw PeopleError.blankName }
            let person = Person(name: name)
            try person.insert(db)
            participant.personId = person.id
            try participant.update(db)
            return person
        }
    }

    public func unlink(participant participantId: UUID) throws {
        try database.queue.write { db in
            guard var participant = try Participant.fetchOne(db, key: participantId.uuidString) else {
                throw PeopleError.participantNotFound
            }
            guard participant.personId != nil else { return }
            participant.personId = nil
            try participant.update(db)
        }
    }

    private static func nonUserParticipant(_ db: Database, _ id: UUID) throws -> Participant {
        guard let participant = try Participant.fetchOne(db, key: id.uuidString) else {
            throw PeopleError.participantNotFound
        }
        guard !participant.isUser else { throw PeopleError.userCannotBePerson }
        return participant
    }

    // MARK: Editing

    /// Changes the given fields. For the optional ones a plain `nil` leaves the field alone and an
    /// explicit `.some(nil)` clears it; blank text clears it too. A blank name is refused.
    public func update(
        _ personId: UUID,
        name: String? = nil,
        organisation: String?? = nil,
        role: String?? = nil,
        notes: String?? = nil
    ) throws {
        try database.queue.write { db in
            guard var person = try Person.fetchOne(db, key: personId.uuidString) else {
                throw PeopleError.personNotFound
            }
            if let name {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw PeopleError.blankName }
                person.name = trimmed
            }
            if let organisation { person.organisation = Self.clean(organisation) }
            if let role { person.role = Self.clean(role) }
            if let notes { person.notes = Self.clean(notes) }
            try person.update(db)
        }
    }

    /// Re-links the participants of `personId` to `target`, keeps the target's fields, fills its empty
    /// fields from the merged person and deletes the merged person row. Nothing else is deleted.
    public func merge(_ personId: UUID, into target: UUID) throws {
        guard personId != target else { throw PeopleError.cannotMergeWithItself }
        try database.queue.write { db in
            guard let merged = try Person.fetchOne(db, key: personId.uuidString),
                  var kept = try Person.fetchOne(db, key: target.uuidString)
            else { throw PeopleError.personNotFound }
            try db.execute(
                sql: "UPDATE participant SET personId = ? WHERE personId = ?",
                arguments: [target.uuidString, personId.uuidString]
            )
            if Self.clean(kept.organisation) == nil { kept.organisation = Self.clean(merged.organisation) }
            if Self.clean(kept.role) == nil { kept.role = Self.clean(merged.role) }
            if Self.clean(kept.notes) == nil { kept.notes = Self.clean(merged.notes) }
            try kept.update(db)
            _ = try Person.deleteOne(db, key: personId.uuidString)
        }
    }

    // MARK: Suggestions

    /// People this participant might be: the same name, or the same first name. Never for the user,
    /// for placeholder names ("Spreker 1", "Speaker S1", "Unknown speaker", "Ik", "Me") or for the
    /// person the participant is already linked to.
    public func suggestions(for participantId: UUID) throws -> [Person] {
        try database.queue.read { db in
            guard let participant = try Participant.fetchOne(db, key: participantId.uuidString) else {
                throw PeopleError.participantNotFound
            }
            guard !participant.isUser, !Self.isPlaceholder(participant.name) else { return [] }
            let name = Self.fold(participant.name)
            let first = name.split(separator: " ").first.map(String.init) ?? name
            return try Person.fetchAll(db)
                .filter { person in
                    guard person.id != participant.personId else { return false }
                    let other = Self.fold(person.name)
                    return other == name || other.split(separator: " ").first.map(String.init) == first
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: Helpers

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Whether a speaker name is only a stand-in ("Spreker 1", "Speaker S1", "Ik") and not a real name.
    public static func isPlaceholderName(_ name: String) -> Bool { isPlaceholder(name) }

    static func isPlaceholder(_ name: String) -> Bool {
        let folded = fold(name)
        if folded.isEmpty { return true }
        return folded.range(
            of: #"^(spreker|sprekers|speaker|onbekende spreker|unknown speaker|onbekend|unknown|ik|me|jij|you)( [a-z]?[0-9]+)?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
