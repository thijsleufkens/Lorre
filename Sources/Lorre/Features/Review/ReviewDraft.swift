import Foundation
import LorreCore
import Observation

/// Where keyboard focus can be inside the review screen.
enum ReviewField: Hashable {
    case list, title, edit, add, pending
}

/// The half-typed things of the review screen: the text being edited, the new outcome being written,
/// which groups are open. Nothing here is saved until the reviewer confirms it.
@MainActor
@Observable
final class ReviewDraft {
    var editingID: UUID?
    var editText = ""
    var addText = ""
    var addKind: OutcomeKind = .myAction
    /// Set once a kind has been picked for a transcript selection; the text field then shows.
    var pendingKind: OutcomeKind?
    var pendingText = ""
    var expandedKinds: Set<OutcomeKind> = []
    var transcriptExpanded = false
    /// The segment a shift-click extends from.
    var anchorSegmentID: UUID?

    func beginEdit(_ outcome: Outcome) {
        editingID = outcome.id
        editText = outcome.text
    }

    func cancelEdit() {
        editingID = nil
        editText = ""
    }

    /// Saves the edited text when it is not empty and changed. Always ends editing.
    func commitEdit(in review: ReviewModel) {
        defer { cancelEdit() }
        guard let id = editingID else { return }
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let outcome = review.outcomes.first(where: { $0.id == id }), outcome.text != text else {
            return
        }
        review.select(id)
        review.updateSelected(text: text)
    }

    func cancelPending() {
        pendingKind = nil
        pendingText = ""
    }

    /// Starts the "turn this selection into an outcome" step with the text prefilled.
    func startPending(kind: OutcomeKind, from review: ReviewModel) {
        let selected = review.segments.filter { review.selectedSegmentIDs.contains($0.id) }
        pendingKind = kind
        pendingText = ViewFormat.firstSentence(of: selected.map(\.text).joined(separator: " "))
    }

    func confirmPending(in review: ReviewModel) {
        guard let kind = pendingKind else { return }
        review.addOutcome(kind: kind, text: pendingText)
        if review.errorMessage == nil { cancelPending() }
    }

    func confirmAdd(in review: ReviewModel) {
        review.addOutcome(kind: addKind, text: addText)
        if review.errorMessage == nil { addText = "" }
    }
}
