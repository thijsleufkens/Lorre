import XCTest
@testable import LorreCore

final class PeopleStoreTests: XCTestCase {
    private var database: LorreDatabase!
    private var conversations: ConversationStore!
    private var review: ReviewStore!
    private var people: PeopleStore!

    override func setUpWithError() throws {
        database = try LorreDatabase.inMemory()
        conversations = ConversationStore(database: database)
        review = ReviewStore(database: database)
        people = PeopleStore(database: database)
    }

    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400) }

    private struct Scene {
        var conversation: Conversation
        var me: Participant
        var other: Participant
    }

    @discardableResult
    private func scene(_ title: String, day: Int, other name: String = "Anna", person: Person? = nil) throws -> Scene {
        let conversation = Conversation(title: title, type: .intake, state: .approved, startedAt: date(day))
        try conversations.save(conversation)
        let me = Participant(conversationId: conversation.id, name: "Thijs", isUser: true)
        let other = Participant(conversationId: conversation.id, personId: nil, name: name)
        try conversations.saveParticipants([me, other])
        if let person { try people.link(participant: other.id, toPerson: person.id) }
        return Scene(conversation: conversation, me: me, other: other)
    }

    private func outcome(
        _ scene: Scene, _ kind: OutcomeKind, _ text: String, owner: Participant? = nil,
        status: OutcomeStatus = .approved
    ) throws -> Outcome {
        let added = try review.addOutcome(
            conversationId: scene.conversation.id, kind: kind, text: text,
            ownerParticipantId: owner?.id, source: .model, now: date(100)
        )
        return try review.setStatus(status, for: added.id, now: date(100))
    }

    private func newPerson(_ name: String, organisation: String? = nil) throws -> Person {
        let s = try scene("seed \(name)", day: -1000, other: name)
        let person = try people.createPerson(from: s.other.id)
        if let organisation { try people.update(person.id, organisation: .some(organisation)) }
        return person
    }

    // MARK: Summaries

    func testSummariesAreOrderedByLastConversationWithCountsAndOpenCount() throws {
        let anna = Person(name: "Anna de Vries", organisation: "Acme")
        let bram = Person(name: "Bram")
        let carla = Person(name: "Carla")
        try database.queue.write { db in
            try anna.insert(db); try bram.insert(db); try carla.insert(db)
        }
        let a1 = try scene("A1", day: 1, other: "Anna", person: anna)
        let a2 = try scene("A2", day: 5, other: "Anna", person: anna)
        try scene("B1", day: 3, other: "Bram", person: bram)
        _ = try outcome(a1, .myAction, "Offerte", owner: a1.me)
        _ = try outcome(a2, .theirCommitment, "Bellen", owner: a2.other)
        _ = try outcome(a2, .decision, "Dinsdag")
        _ = try outcome(a2, .openPoint, "Prijs", status: .rejected)
        _ = try outcome(a2, .followUpHook, "Januari", status: .proposed)

        let list = try people.people()
        XCTAssertEqual(list.map(\.person.name), ["Anna de Vries", "Bram", "Carla"])
        XCTAssertEqual(list[0].conversationCount, 2)
        XCTAssertEqual(list[0].lastConversationAt, date(5))
        XCTAssertEqual(list[0].openCount, 2)
        XCTAssertEqual(list[1].conversationCount, 1)
        XCTAssertEqual(list[1].openCount, 0)
        XCTAssertEqual(list[2].conversationCount, 0)
        XCTAssertNil(list[2].lastConversationAt)
    }

    func testSearchIgnoresCaseAndDiacriticsAndLooksAtOrganisation() throws {
        let rene = Person(name: "René", organisation: "Acme")
        let sofie = Person(name: "Sofie", role: "Controller")
        try database.queue.write { db in try rene.insert(db); try sofie.insert(db) }
        XCTAssertEqual(try people.people(matching: "rene").map(\.person.name), ["René"])
        XCTAssertEqual(try people.people(matching: "ACME").map(\.person.name), ["René"])
        XCTAssertEqual(try people.people(matching: "controller").map(\.person.name), ["Sofie"])
        XCTAssertEqual(try people.people(matching: "  ").count, 2)
        XCTAssertTrue(try people.people(matching: "zzz").isEmpty)
    }

    func testTheUserIsNeverListed() throws {
        let s = try scene("A", day: 1)
        try people.createPerson(from: s.other.id)
        XCTAssertEqual(try people.people().map(\.person.name), ["Anna"])
        // Even a legacy user participant that points at a person does not count as a conversation.
        let ghost = Person(name: "Ghost")
        try database.queue.write { db in
            try ghost.insert(db)
            var me = s.me
            me.personId = ghost.id
            try me.update(db)
        }
        let list = try people.people()
        XCTAssertEqual(list.first { $0.person.id == ghost.id }?.conversationCount, 0)
        XCTAssertNil(try people.brief(ghost.id)?.conversations.first)
    }

    // MARK: Brief

    func testBriefGroupsByKindAndOwnerAcrossTwoConversations() throws {
        let anna = Person(name: "Anna")
        let bram = Person(name: "Bram")
        try database.queue.write { db in try anna.insert(db); try bram.insert(db) }
        let old = try scene("Old", day: 1, person: anna)
        let new = try scene("New", day: 9, person: anna)
        // Bram joins the newer conversation as a third speaker.
        let third = Participant(conversationId: new.conversation.id, name: "Bram")
        try conversations.saveParticipants([third])
        try people.link(participant: third.id, toPerson: bram.id)

        let mine = try outcome(old, .myAction, "Offerte", owner: old.me)
        let hers = try outcome(old, .theirCommitment, "Tabel", owner: old.other)
        _ = try outcome(new, .theirCommitment, "Van Bram", owner: third)
        let open = try outcome(new, .openPoint, "Prijs")
        let hook = try outcome(old, .followUpHook, "Januari")
        let note = try outcome(new, .personNote, "Nu operations")
        let oldDecision = try outcome(old, .decision, "Oud besluit")
        let newDecision = try outcome(new, .decision, "Nieuw besluit")
        _ = try outcome(new, .information, "Info")

        let brief = try XCTUnwrap(try people.brief(anna.id))
        XCTAssertEqual(brief.conversations.map(\.title), ["New", "Old"])
        XCTAssertEqual(brief.myActions.map(\.outcome.id), [mine.id])
        XCTAssertEqual(brief.myActions.first?.ownerName, "Thijs")
        XCTAssertEqual(brief.theirCommitments.map(\.outcome.id), [hers.id])
        XCTAssertEqual(brief.theirCommitments.first?.ownerName, "Anna")
        XCTAssertEqual(brief.openPoints.map(\.outcome.id), [open.id])
        XCTAssertEqual(brief.hooks.map(\.outcome.id), [hook.id])
        XCTAssertEqual(brief.notes.map(\.outcome.id), [note.id])
        XCTAssertEqual(brief.lastDecisions.map(\.outcome.id), [newDecision.id])
        XCTAssertFalse(brief.lastDecisions.contains { $0.outcome.id == oldDecision.id })

        let bramBrief = try XCTUnwrap(try people.brief(bram.id))
        XCTAssertEqual(bramBrief.theirCommitments.map(\.outcome.text), ["Van Bram"])
        XCTAssertEqual(bramBrief.conversations.map(\.title), ["New"])
    }

    func testBriefHasOnlyApprovedOutcomes() throws {
        let anna = Person(name: "Anna")
        try database.queue.write { db in try anna.insert(db) }
        let s = try scene("A", day: 1, person: anna)
        _ = try outcome(s, .myAction, "Goedgekeurd", owner: s.me)
        _ = try outcome(s, .myAction, "Voorgesteld", owner: s.me, status: .proposed)
        _ = try outcome(s, .openPoint, "Afgewezen", status: .rejected)
        _ = try outcome(s, .decision, "Besluit", status: .rejected)
        let brief = try XCTUnwrap(try people.brief(anna.id))
        XCTAssertEqual(brief.myActions.map(\.outcome.text), ["Goedgekeurd"])
        XCTAssertTrue(brief.openPoints.isEmpty)
        XCTAssertTrue(brief.lastDecisions.isEmpty)
        XCTAssertNil(try people.brief(UUID()))
    }

    func testBriefForUpcomingMatchesNames() throws {
        let rene = Person(name: "René Jansen")
        let anna = Person(name: "Anna")
        try database.queue.write { db in try rene.insert(db); try anna.insert(db) }
        let briefs = try people.brief(forUpcoming: ["rene jansen", "Nobody", " "])
        XCTAssertEqual(briefs.map(\.person.id), [rene.id])
        XCTAssertTrue(try people.brief(forUpcoming: []).isEmpty)
    }

    // MARK: Linking

    func testLinkUnlinkAndCreatePerson() throws {
        let s = try scene("A", day: 1)
        let created = try people.createPerson(from: s.other.id)
        XCTAssertEqual(created.name, "Anna")
        XCTAssertEqual(try conversations.participants(conversationId: s.conversation.id).first { $0.id == s.other.id }?.personId, created.id)

        try people.unlink(participant: s.other.id)
        XCTAssertNil(try conversations.participants(conversationId: s.conversation.id).first { $0.id == s.other.id }?.personId)
        try people.unlink(participant: s.other.id) // already unlinked: fine

        let again = try people.link(participant: s.other.id, toPerson: created.id)
        XCTAssertEqual(again, created)
        XCTAssertEqual(try people.people().first?.conversationCount, 1)
    }

    func testTheUserIsRefused() throws {
        let s = try scene("A", day: 1)
        let anna = try people.createPerson(from: s.other.id)
        XCTAssertThrowsError(try people.createPerson(from: s.me.id)) {
            XCTAssertEqual($0 as? PeopleStore.PeopleError, .userCannotBePerson)
        }
        XCTAssertThrowsError(try people.link(participant: s.me.id, toPerson: anna.id)) {
            XCTAssertEqual($0 as? PeopleStore.PeopleError, .userCannotBePerson)
        }
        XCTAssertThrowsError(try people.link(participant: s.other.id, toPerson: UUID())) {
            XCTAssertEqual($0 as? PeopleStore.PeopleError, .personNotFound)
        }
        XCTAssertThrowsError(try people.createPerson(from: UUID())) {
            XCTAssertEqual($0 as? PeopleStore.PeopleError, .participantNotFound)
        }
        XCTAssertEqual(try people.people().count, 1)
    }

    func testBlankNamesAreRefused() throws {
        let s = try scene("A", day: 1, other: "   ")
        XCTAssertThrowsError(try people.createPerson(from: s.other.id)) {
            XCTAssertEqual($0 as? PeopleStore.PeopleError, .blankName)
        }
        let anna = try newPerson("Anna")
        XCTAssertThrowsError(try people.update(anna.id, name: "  ")) {
            XCTAssertEqual($0 as? PeopleStore.PeopleError, .blankName)
        }
        XCTAssertEqual(try people.brief(anna.id)?.person.name, "Anna")
    }

    // MARK: Update

    func testUpdateChangesFieldsAndExplicitNilClears() throws {
        let anna = try newPerson("Anna", organisation: "Acme")
        try people.update(anna.id, name: " Anna de Vries ", role: .some("Controller"), notes: .some("Let op"))
        var stored = try XCTUnwrap(try people.brief(anna.id)?.person)
        XCTAssertEqual(stored.name, "Anna de Vries")
        XCTAssertEqual(stored.organisation, "Acme") // untouched
        XCTAssertEqual(stored.role, "Controller")
        XCTAssertEqual(stored.notes, "Let op")

        try people.update(anna.id, organisation: .some(nil), notes: .some("  "))
        stored = try XCTUnwrap(try people.brief(anna.id)?.person)
        XCTAssertNil(stored.organisation)
        XCTAssertNil(stored.notes)
        XCTAssertEqual(stored.role, "Controller")

        XCTAssertThrowsError(try people.update(UUID(), name: "X")) {
            XCTAssertEqual($0 as? PeopleStore.PeopleError, .personNotFound)
        }
    }

    // MARK: Merge

    func testMergeRelinksFillsEmptyFieldsAndDeletesOnlyTheMergedPerson() throws {
        let keep = Person(name: "Anna de Vries", organisation: nil, role: "Controller", notes: nil)
        let dupe = Person(name: "Anna Devries", organisation: "Acme", role: "Manager", notes: "Notitie")
        try database.queue.write { db in try keep.insert(db); try dupe.insert(db) }
        let s1 = try scene("S1", day: 1, person: keep)
        let s2 = try scene("S2", day: 2, person: dupe)
        let item = try outcome(s2, .openPoint, "Prijs")

        try people.merge(dupe.id, into: keep.id)

        let list = try people.people()
        XCTAssertEqual(list.map(\.person.id), [keep.id])
        XCTAssertEqual(list[0].conversationCount, 2)
        XCTAssertEqual(list[0].person.organisation, "Acme")
        XCTAssertEqual(list[0].person.role, "Controller") // the target's own value wins
        XCTAssertEqual(list[0].person.notes, "Notitie")
        let participants = try conversations.participants(conversationId: s2.conversation.id)
        XCTAssertEqual(participants.first { $0.id == s2.other.id }?.personId, keep.id)
        XCTAssertEqual(try people.brief(keep.id)?.openPoints.map(\.outcome.id), [item.id])
        XCTAssertNil(try people.brief(dupe.id))
        // Conversations and outcomes survive.
        XCTAssertNotNil(try conversations.conversation(id: s1.conversation.id))
        XCTAssertEqual(try review.outcomes(conversationId: s2.conversation.id).count, 1)
    }

    func testMergeFailureCases() throws {
        let a = try newPerson("A")
        XCTAssertThrowsError(try people.merge(a.id, into: a.id)) {
            XCTAssertEqual($0 as? PeopleStore.PeopleError, .cannotMergeWithItself)
        }
        XCTAssertThrowsError(try people.merge(a.id, into: UUID())) {
            XCTAssertEqual($0 as? PeopleStore.PeopleError, .personNotFound)
        }
        XCTAssertThrowsError(try people.merge(UUID(), into: a.id))
        XCTAssertEqual(try people.people().count, 1)
    }

    // MARK: Suggestions

    func testSuggestionsMatchNameOrFirstNameIgnoringCaseAndDiacritics() throws {
        let rene = Person(name: "René Jansen")
        let rene2 = Person(name: "Rene Bakker")
        let other = Person(name: "Bram Jansen")
        try database.queue.write { db in try rene.insert(db); try rene2.insert(db); try other.insert(db) }
        let s = try scene("A", day: 1, other: "RENÉ")
        XCTAssertEqual(try people.suggestions(for: s.other.id).map(\.name), ["Rene Bakker", "René Jansen"])
        let exact = try scene("B", day: 2, other: "bram jansen")
        XCTAssertEqual(try people.suggestions(for: exact.other.id).map(\.name), ["Bram Jansen"])
        let none = try scene("C", day: 3, other: "Zoë")
        XCTAssertTrue(try people.suggestions(for: none.other.id).isEmpty)
    }

    func testNoSuggestionsForPlaceholdersTheUserOrTheLinkedPerson() throws {
        let anna = Person(name: "Spreker Anna")
        let speaker = Person(name: "Speaker")
        let unknown = Person(name: "Unknown")
        let ik = Person(name: "Ik")
        try database.queue.write { db in
            try anna.insert(db); try speaker.insert(db); try unknown.insert(db); try ik.insert(db)
        }
        for name in ["Spreker 1", "Speaker S1", "Unknown speaker", "Ik", "Me", "  ", "Onbekende spreker"] {
            let s = try scene(name, day: 1, other: name)
            XCTAssertTrue(try people.suggestions(for: s.other.id).isEmpty, name)
        }
        let s = try scene("U", day: 2, other: "Anna")
        XCTAssertTrue(try people.suggestions(for: s.me.id).isEmpty)
        XCTAssertTrue(try people.suggestions(for: s.other.id).isEmpty) // "Spreker Anna" starts with another word
        let linked = try scene("L", day: 3, other: "Spreker Anna", person: anna)
        XCTAssertFalse(try people.suggestions(for: linked.other.id).contains { $0.id == anna.id })
        XCTAssertThrowsError(try people.suggestions(for: UUID()))
    }
}
