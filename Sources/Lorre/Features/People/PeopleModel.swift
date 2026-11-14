import Foundation
import LorreCore
import Observation

/// State behind the people list and one person's page.
///
/// Every change goes through `PeopleStore`, after which the model reloads from the database.
@MainActor
@Observable
final class PeopleModel {
    private(set) var people: [PersonSummary] = []
    /// Everyone, whatever the search says: for the empty state and for choosing who to merge with.
    private(set) var allPeople: [PersonSummary] = []
    var searchText = "" {
        didSet { if searchText != oldValue { load() } }
    }
    var selectedPersonID: UUID? {
        didSet { if selectedPersonID != oldValue { loadBrief() } }
    }
    private(set) var brief: PersonBrief?
    private(set) var errorMessage: String?

    @ObservationIgnored private let database: LorreDatabase

    init(database: LorreDatabase) {
        self.database = database
    }

    private var store: PeopleStore { PeopleStore(database: database) }

    func load() {
        do {
            people = try store.people(matching: searchText)
            allPeople = searchText.isEmpty ? people : try store.people()
        } catch {
            errorMessage = error.localizedDescription
        }
        loadBrief()
    }

    private func loadBrief() {
        guard let id = selectedPersonID else {
            brief = nil
            return
        }
        do {
            brief = try store.brief(id)
        } catch {
            errorMessage = error.localizedDescription
            brief = nil
        }
        // A person who no longer exists cannot stay selected.
        if brief == nil, selectedPersonID == id { selectedPersonID = nil }
    }

    func select(_ id: UUID?) {
        selectedPersonID = id
    }

    func rename(_ id: UUID, to name: String) { perform { try store.update(id, name: name) } }
    func setOrganisation(_ id: UUID, _ value: String?) { perform { try store.update(id, organisation: .some(value)) } }
    func setRole(_ id: UUID, _ value: String?) { perform { try store.update(id, role: .some(value)) } }
    func setNotes(_ id: UUID, _ value: String?) { perform { try store.update(id, notes: .some(value)) } }

    func merge(_ id: UUID, into target: UUID) {
        let wasSelected = selectedPersonID == id
        guard perform({ try store.merge(id, into: target) }) else { return }
        if wasSelected { select(target) }
    }

    /// Runs a change, sets or clears the error message, and reloads. Returns whether it worked.
    @discardableResult
    private func perform(_ change: () throws -> Void) -> Bool {
        var succeeded = true
        do {
            try change()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            succeeded = false
        }
        load()
        return succeeded
    }
}


// MARK: Brief layout (additive)

/// The groups of "Voor het volgende gesprek", in the order they are shown.
enum BriefGroup: CaseIterable {
    case myActions, theirCommitments, openPoints, hooks, notes, lastDecisions

    /// The groups that belong under "Voor het volgende gesprek"; the other two follow below it.
    var isForNextConversation: Bool {
        switch self {
        case .myActions, .theirCommitments, .openPoints, .hooks: true
        case .notes, .lastDecisions: false
        }
    }
}

extension PeopleModel {
    func items(_ group: BriefGroup) -> [PersonBrief.Item] {
        guard let brief else { return [] }
        switch group {
        case .myActions: return brief.myActions
        case .theirCommitments: return brief.theirCommitments
        case .openPoints: return brief.openPoints
        case .hooks: return brief.hooks
        case .notes: return brief.notes
        case .lastDecisions: return brief.lastDecisions
        }
    }

    /// Groups that have items; empty groups are never shown.
    var visibleGroups: [BriefGroup] {
        BriefGroup.allCases.filter { !items($0).isEmpty }
    }

    /// True when the brief has nothing to prepare with.
    var isBriefEmpty: Bool { visibleGroups.isEmpty }

    /// The people the selected person could be merged into.
    var mergeTargets: [PersonSummary] {
        allPeople.filter { $0.id != selectedPersonID }
    }
}
