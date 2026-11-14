import Foundation
import LorreCore
import Observation

enum WorkspaceSection: String, CaseIterable {
    case today, conversations, people
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
    /// The people list and the page of one person.
    let people: PeopleModel
    /// What the calendar says is coming up.
    let comingUp: ComingUpModel

    /// Setting it runs the search.
    var searchText: String = "" {
        didSet { if searchText != oldValue { runSearch() } }
    }

    @ObservationIgnored private let database: LorreDatabase
    @ObservationIgnored private let paths: LorrePaths
    @ObservationIgnored private let makePlayer: @MainActor () -> any EvidencePlaying

    init(
        database: LorreDatabase, paths: LorrePaths,
        calendar: any CalendarSource = NoCalendarSource(),
        makePlayer: @escaping @MainActor () -> any EvidencePlaying
    ) {
        self.database = database
        self.paths = paths
        self.makePlayer = makePlayer
        self.people = PeopleModel(database: database)
        self.comingUp = ComingUpModel(source: calendar, database: database)
    }

    /// The small settings kept in the same database (first-run state, the user's name).
    var settings: SettingsStore { SettingsStore(database: database) }

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
        people.load()
        Task { await comingUp.reload() }
    }

    func open(_ conversationID: UUID) {
        review?.stopPlayback()
        let model = ReviewModel(
            conversationID: conversationID, database: database, paths: paths, player: makePlayer()
        )
        model.onShowPerson = { [weak self] id in self?.showPerson(id) }
        model.load()
        review = model
    }

    /// Closes the review, switches to the People section and selects this person.
    func showPerson(_ id: UUID) {
        review?.stopPlayback()
        review = nil
        section = .people
        refresh()
        people.select(id)
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
