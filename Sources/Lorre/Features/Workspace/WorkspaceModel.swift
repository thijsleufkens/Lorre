import Foundation
import LorreCore
import Observation

enum WorkspaceSection: String, CaseIterable {
    case today, conversations
}

/// State behind the main window: which conversations wait, which are busy, search, and the
/// conversation that is open for review.
@MainActor
@Observable
final class WorkspaceModel {
    var section: WorkspaceSection = .today

    /// Transcribed and waiting for the reviewer, newest first.
    private(set) var toReview: [ConversationSummary] = []
    /// Recording, processing or interrupted; imported conversations are never in progress.
    private(set) var inProgress: [ConversationSummary] = []
    /// Everything, newest first.
    private(set) var all: [ConversationSummary] = []
    private(set) var searchHits: [SearchHit] = []
    private(set) var review: ReviewModel?
    private(set) var errorMessage: String?

    /// Setting it runs the search.
    var searchText: String = "" {
        didSet { if searchText != oldValue { runSearch() } }
    }

    @ObservationIgnored private let database: LorreDatabase
    @ObservationIgnored private let paths: LorrePaths
    @ObservationIgnored private let makePlayer: @MainActor () -> any EvidencePlaying

    init(database: LorreDatabase, paths: LorrePaths, makePlayer: @escaping @MainActor () -> any EvidencePlaying) {
        self.database = database
        self.paths = paths
        self.makePlayer = makePlayer
    }

    func refresh() {
        do {
            all = try ConversationStore(database: database).listConversations()
            toReview = try ReviewStore(database: database).conversationsToReview()
            let busy: Set<ConversationState> = [.recording, .processing, .interrupted]
            inProgress = all.filter { busy.contains($0.conversation.state) && $0.conversation.importedAt == nil }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        runSearch()
    }

    func open(_ conversationID: UUID) {
        review?.stopPlayback()
        let model = ReviewModel(
            conversationID: conversationID, database: database, paths: paths, player: makePlayer()
        )
        model.load()
        review = model
    }

    func closeReview() {
        review?.stopPlayback()
        review = nil
        refresh()
    }

    private func runSearch() {
        do {
            searchHits = try SearchStore(database: database).search(searchText)
        } catch {
            searchHits = []
            errorMessage = error.localizedDescription
        }
    }
}
