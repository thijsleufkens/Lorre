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
