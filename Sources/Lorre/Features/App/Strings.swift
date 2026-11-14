import Foundation
import LorreCore

/// Every visible text of the workspace, review and records-settings screens, in both languages.
/// Dutch is the leading language. Texts with numbers are functions, so singular and plural stay right.
struct Strings: Sendable {
    let language: LorreLanguage

    static let dutch = Strings(.dutch)
    static let english = Strings(.english)

    static var current: Strings {
        LorreLanguage.current == .dutch ? .dutch : .english
    }

    // MARK: Window
    let sectionToday: String
    let sectionConversations: String
    let record: String
    let recordHelp: String
    let stop: String
    let stopHelp: String
    let starting: String
    let stopping: String
    let recorderUnavailable: String
    let dismiss: String
    let dismissHelp: String
    let untitledConversation: String

    // MARK: Today
    let toReviewHeader: String
    let inProgressHeader: String
    let reviewButton: String
    let reviewButtonHelp: String
    let todayEmpty: String
    let stateRecording: String
    let stateProcessing: String
    let stateInterrupted: String
    let stateFailed: String
    let stateToReview: String
    let stateDone: String
    let stateChanged: String

    // MARK: Conversations
    let searchPlaceholder: String
    let searchHelp: String
    let conversationsEmpty: String
    let notReadyHelp: String
    let todayWord: String
    let yesterdayWord: String

    // MARK: Review: header
    let back: String
    let backHelp: String
    let titleHelp: String
    let conversationType: String
    let conversationTypeHelp: String
    let participantMenuHelp: String
    let renameParticipant: String
    let renamePrompt: String
    let renameConfirm: String
    let cancel: String
    let thisIsMe: String
    let mergeInto: String

    // MARK: Review: outcomes
    let approve: String
    let reject: String
    let edit: String
    let approvedLabel: String
    let proposedLabel: String
    let owner: String
    let ownerNone: String
    let ownerMenuHelp: String
    let addOutcome: String
    let addPlaceholder: String
    let addConfirm: String
    let addKindHelp: String
    let noOutcomes: String
    let showGroup: String
    let hideGroup: String

    // MARK: Review: evidence and transcript
    let evidenceHeader: String
    let evidenceSelectOne: String
    let evidenceNone: String
    let playEvidence: String
    let stopPlaying: String
    let noAudio: String
    let fullTranscript: String
    let transcriptEmpty: String
    let selectionPrompt: String
    let clearSelection: String
    let unknownSpeaker: String
    let speakerMenuHelp: String
    let playFragment: String

    // MARK: Review: footer
    let keyboardHints: String
    let finish: String
    let finishHelp: String
    let savedTitle: String
    let showInFinder: String
    let done: String

    // MARK: Settings
    let recordsTab: String
    let exportFolder: String
    let exportFolderHelp: String
    let chooseFolder: String
    let chooseFolderPrompt: String
    let useDefaultFolder: String
    let yourName: String
    let yourNameHelp: String
    let proposalModel: String
    let proposalModelHelp: String

    // MARK: Units
    let hourUnit: String
    let minuteUnit: String
    let lessThanAMinute: String

    private init(_ language: LorreLanguage) {
        self.language = language
        func t(_ nl: String, _ en: String) -> String { language == .dutch ? nl : en }

        sectionToday = t("Vandaag", "Today")
        sectionConversations = t("Gesprekken", "Conversations")
        record = t("Opnemen", "Record")
        recordHelp = t("Begin met opnemen", "Start recording")
        stop = t("Stop", "Stop")
        stopHelp = t("Stop de opname", "Stop recording")
        starting = t("Starten…", "Starting…")
        stopping = t("Stoppen…", "Stopping…")
        recorderUnavailable = t("Opnemen is nu niet beschikbaar.", "Recording is not available right now.")
        dismiss = t("Sluiten", "Dismiss")
        dismissHelp = t("Verberg dit bericht", "Hide this message")
        untitledConversation = t("Gesprek zonder titel", "Untitled conversation")

        toReviewHeader = t("Na te kijken", "To review")
        inProgressHeader = t("Bezig", "In progress")
        reviewButton = t("Nakijken", "Review")
        reviewButtonHelp = t("Kijk de uitkomsten van dit gesprek na", "Check what came out of this conversation")
        todayEmpty = t(
            "Niets na te kijken. Start een opname zodra je een gesprek hebt.",
            "Nothing to review. Start a recording when you have a conversation."
        )
        stateRecording = t("Wordt opgenomen", "Recording")
        stateProcessing = t("Wordt uitgewerkt", "Being transcribed")
        stateInterrupted = t("Onderbroken", "Interrupted")
        stateFailed = t("Uitwerken is mislukt", "Transcription failed")
        stateToReview = t("Na te kijken", "To review")
        stateDone = t("Klaar", "Done")
        stateChanged = t("Aangepast", "Changed")

        searchPlaceholder = t("Zoek in alle gesprekken", "Search all conversations")
        searchHelp = t("Zoek naar woorden die in een gesprek zijn gezegd", "Search for words said in a conversation")
        conversationsEmpty = t("Er zijn nog geen gesprekken.", "There are no conversations yet.")
        notReadyHelp = t("Dit gesprek is nog niet uitgewerkt", "This conversation is not transcribed yet")
        todayWord = t("vandaag", "today")
        yesterdayWord = t("gisteren", "yesterday")

        back = t("Terug", "Back")
        backHelp = t("Terug naar het overzicht", "Back to the overview")
        titleHelp = t("Klik om de titel aan te passen", "Click to change the title")
        conversationType = t("Soort gesprek", "Type of conversation")
        conversationTypeHelp = t("Kies wat voor gesprek dit was", "Choose what kind of conversation this was")
        participantMenuHelp = t("Aanpassen wie dit is", "Change who this is")
        renameParticipant = t("Naam wijzigen…", "Rename…")
        renamePrompt = t("Nieuwe naam", "New name")
        renameConfirm = t("Wijzig", "Rename")
        cancel = t("Annuleer", "Cancel")
        thisIsMe = t("Dit ben ik", "This is me")
        mergeInto = t("Samenvoegen met…", "Merge into…")

        approve = t("Goedkeuren", "Approve")
        reject = t("Afwijzen", "Reject")
        edit = t("Aanpassen", "Edit")
        approvedLabel = t("Goedgekeurd", "Approved")
        proposedLabel = t("Voorgesteld", "Proposed")
        owner = t("Van wie", "Whose")
        ownerNone = t("Niemand", "Nobody")
        ownerMenuHelp = t("Kies van wie dit punt is", "Choose who this belongs to")
        addOutcome = t("+ Uitkomst toevoegen", "+ Add outcome")
        addPlaceholder = t("Wat is er afgesproken of besloten?", "What was agreed or decided?")
        addConfirm = t("Toevoegen", "Add")
        addKindHelp = t("Kies wat voor soort uitkomst dit is", "Choose what kind of outcome this is")
        noOutcomes = t(
            "Er zijn geen uitkomsten gevonden. Voeg zelf iets toe, of selecteer een stuk van het gesprek rechts.",
            "No outcomes were found. Add one yourself, or select part of the conversation on the right."
        )
        showGroup = t("Toon", "Show")
        hideGroup = t("Verberg", "Hide")

        evidenceHeader = t("Wat er gezegd is", "What was said")
        evidenceSelectOne = t(
            "Kies links een punt om te zien waar het vandaan komt.",
            "Pick an item on the left to see where it came from."
        )
        evidenceNone = t(
            "Voor dit punt is geen stukje gesprek bewaard.",
            "No part of the conversation is kept for this item."
        )
        playEvidence = t("Beluister dit moment", "Listen to this moment")
        stopPlaying = t("Stop met afspelen", "Stop playing")
        noAudio = t(
            "Het geluid van dit gesprek is niet meer beschikbaar.",
            "The audio of this conversation is no longer available."
        )
        fullTranscript = t("Hele gesprek", "Whole conversation")
        transcriptEmpty = t("Er is geen tekst van dit gesprek.", "There is no text for this conversation.")
        selectionPrompt = t("Maak er een uitkomst van:", "Turn it into an outcome:")
        clearSelection = t("Selectie wissen", "Clear selection")
        unknownSpeaker = t("Onbekend", "Unknown")
        speakerMenuHelp = t("Kies wie dit zei", "Choose who said this")
        playFragment = t("Speel af vanaf hier", "Play from here")

        keyboardHints = t(
            "A goedkeuren · X afwijzen · E aanpassen · Spatie afspelen · N nieuw",
            "A approve · X reject · E edit · Space play · N new"
        )
        finish = t("Alles goedkeuren en afronden", "Approve all and finish")
        finishHelp = t(
            "Keur alles goed wat nog openstaat en bewaar het verslag",
            "Approve everything still open and save the record"
        )
        savedTitle = t("Klaar, het verslag is bewaard", "Done, the record is saved")
        showInFinder = t("Toon in Finder", "Show in Finder")
        done = t("Klaar", "Done")

        recordsTab = t("Verslagen", "Records")
        exportFolder = t("Map voor verslagen", "Folder for records")
        exportFolderHelp = t(
            "Hier bewaart Lorre het verslag van elk gesprek dat je afrondt.",
            "Lorre saves the record of every conversation you finish here."
        )
        chooseFolder = t("Kies map…", "Choose folder…")
        chooseFolderPrompt = t("Kies", "Choose")
        useDefaultFolder = t("Standaard", "Default")
        yourName = t("Jouw naam", "Your name")
        yourNameHelp = t(
            "Zo noemt Lorre jou in teksten en verslagen.",
            "This is how Lorre refers to you in texts and records."
        )
        proposalModel = t("Model voor voorstellen", "Model for proposals")
        proposalModelHelp = t(
            "Naam van een model in Ollama op deze Mac, bijvoorbeeld gemma4:e4b. Laat leeg om zelf alle punten toe te voegen. Er gaat niets naar buiten.",
            "Name of a model in Ollama on this Mac, for example gemma4:e4b. Leave empty to add every point yourself. Nothing leaves this Mac."
        )

        hourUnit = t("u", "h")
        minuteUnit = t("min", "min")
        lessThanAMinute = t("< 1 min", "< 1 min")
    }

    // MARK: Texts with numbers

    func toReviewCount(_ n: Int) -> String {
        switch (language, n) {
        case (.dutch, 1): "1 gesprek na te kijken"
        case (.dutch, _): "\(n) gesprekken na te kijken"
        case (.english, 1): "1 conversation to review"
        case (.english, _): "\(n) conversations to review"
        }
    }

    /// The line on a review card, for example "3 voorgestelde uitkomsten".
    func proposedOutcomesLine(_ n: Int) -> String {
        switch (language, n) {
        case (.dutch, 1): "1 voorgestelde uitkomst"
        case (.dutch, _): "\(n) voorgestelde uitkomsten"
        case (.english, 1): "1 proposed outcome"
        case (.english, _): "\(n) proposed outcomes"
        }
    }

    func pendingCount(_ n: Int) -> String {
        switch (language, n) {
        case (.dutch, 0): "Alles is beoordeeld"
        case (.dutch, 1): "1 nog te beoordelen"
        case (.dutch, _): "\(n) nog te beoordelen"
        case (.english, 0): "Everything is judged"
        case (.english, 1): "1 left to judge"
        case (.english, _): "\(n) left to judge"
        }
    }

    func selectedFragments(_ n: Int) -> String {
        switch (language, n) {
        case (.dutch, 1): "1 stuk geselecteerd"
        case (.dutch, _): "\(n) stukken geselecteerd"
        case (.english, 1): "1 part selected"
        case (.english, _): "\(n) parts selected"
        }
    }

    func noHits(for query: String) -> String {
        switch language {
        case .dutch: "Niets gevonden voor “\(query)”."
        case .english: "Nothing found for “\(query)”."
        }
    }

    func savedAt(_ path: String) -> String {
        switch language {
        case .dutch: "Je vindt het in \(path)"
        case .english: "You can find it in \(path)"
        }
    }

    func playFrom(_ clock: String) -> String {
        switch language {
        case .dutch: "Beluister vanaf \(clock)"
        case .english: "Listen from \(clock)"
        }
    }
}
