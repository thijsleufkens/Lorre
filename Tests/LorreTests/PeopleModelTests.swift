import LorreCore
import XCTest
@testable import Lorre

@MainActor
final class PeopleModelTests: XCTestCase {
    private var database: LorreDatabase!
    private var store: PeopleStore!
    private var model: PeopleModel!
    private var annaID: UUID!
    private var bramID: UUID!

    override func setUpWithError() throws {
        database = try LorreDatabase.inMemory()
        store = PeopleStore(database: database)
        let conversations = ConversationStore(database: database)
        let review = ReviewStore(database: database)
        var ids: [UUID] = []
        for (day, name) in [(1, "Anna"), (5, "Bram")] {
            let conversation = Conversation(
                title: "Gesprek \(name)", type: .intake, state: .approved,
                startedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400)
            )
            try conversations.save(conversation)
            let me = Participant(conversationId: conversation.id, name: "Thijs", isUser: true)
            let other = Participant(conversationId: conversation.id, name: name)
            try conversations.saveParticipants([me, other])
            ids.append(try store.createPerson(from: other.id).id)
            let outcome = try review.addOutcome(
                conversationId: conversation.id, kind: .myAction, text: "Mailen \(name)",
                ownerParticipantId: me.id, source: .user
            )
            XCTAssertEqual(outcome.status, .approved)
        }
        annaID = ids[0]
        bramID = ids[1]
        model = PeopleModel(database: database)
        model.load()
    }

    func testLoadListsPeopleNewestFirst() {
        XCTAssertEqual(model.people.map(\.person.name), ["Bram", "Anna"])
        XCTAssertNil(model.brief)
        XCTAssertNil(model.errorMessage)
    }

    func testSearchTextReloads() {
        model.searchText = "ann"
        XCTAssertEqual(model.people.map(\.person.name), ["Anna"])
        model.searchText = ""
        XCTAssertEqual(model.people.count, 2)
    }

    func testSelectLoadsTheBrief() {
        model.select(annaID)
        XCTAssertEqual(model.selectedPersonID, annaID)
        XCTAssertEqual(model.brief?.person.name, "Anna")
        XCTAssertEqual(model.brief?.myActions.map(\.outcome.text), ["Mailen Anna"])
        model.select(nil)
        XCTAssertNil(model.brief)
    }

    func testEditsGoThroughTheStoreAndReload() throws {
        model.select(annaID)
        model.rename(annaID, to: "Anna de Vries")
        XCTAssertEqual(model.brief?.person.name, "Anna de Vries")
        XCTAssertTrue(model.people.contains { $0.person.name == "Anna de Vries" })

        model.setOrganisation(annaID, "Acme")
        model.setRole(annaID, "Controller")
        model.setNotes(annaID, "Let op")
        XCTAssertEqual(model.brief?.person.organisation, "Acme")
        XCTAssertEqual(model.brief?.person.role, "Controller")
        XCTAssertEqual(model.brief?.person.notes, "Let op")
        XCTAssertEqual(model.people.first { $0.id == annaID }?.person.organisation, "Acme")

        model.setOrganisation(annaID, nil)
        XCTAssertNil(model.brief?.person.organisation)
        XCTAssertEqual(model.brief?.person.role, "Controller")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(try store.brief(annaID)?.person.name, "Anna de Vries")
    }

    func testErrorsAreSurfacedAndClearedByTheNextSuccess() {
        model.select(annaID)
        model.rename(annaID, to: "   ")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.brief?.person.name, "Anna")
        model.rename(annaID, to: "Anna B")
        XCTAssertNil(model.errorMessage)
        model.merge(annaID, into: annaID)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.people.count, 2)
    }

    func testMergeReloadsAndFollowsTheSelectionToTheTarget() {
        model.select(annaID)
        model.merge(annaID, into: bramID)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.people.map(\.person.name), ["Bram"])
        XCTAssertEqual(model.people.first?.conversationCount, 2)
        XCTAssertEqual(model.selectedPersonID, bramID)
        XCTAssertEqual(model.brief?.myActions.count, 2)
    }

    func testAPersonThatVanishedIsDeselected() throws {
        model.select(annaID)
        try store.merge(annaID, into: bramID)
        model.load()
        XCTAssertNil(model.selectedPersonID)
        XCTAssertNil(model.brief)
        XCTAssertEqual(model.people.count, 1)
    }

    func testVisibleGroupsLeaveEmptyOnesOutAndMergeTargetsExcludeTheSelected() {
        XCTAssertTrue(model.visibleGroups.isEmpty, "nothing selected")
        model.select(annaID)
        XCTAssertEqual(model.visibleGroups, [.myActions])
        XCTAssertFalse(model.isBriefEmpty)
        XCTAssertEqual(model.items(.myActions).map(\.outcome.text), ["Mailen Anna"])
        XCTAssertTrue(model.items(.hooks).isEmpty)
        XCTAssertEqual(model.mergeTargets.map(\.person.name), ["Bram"])
        model.searchText = "zzz"
        XCTAssertEqual(model.mergeTargets.map(\.person.name), ["Bram"], "the search does not hide merge targets")
        XCTAssertEqual(model.allPeople.count, 2)
    }
}
