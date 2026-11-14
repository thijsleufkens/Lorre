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
    let sectionPickerLabel: String
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
    let comingUpHeader: String
    let calendarPrompt: String
    let calendarAllow: String
    let calendarAllowHelp: String
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
    let tomorrowWord: String

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

    // MARK: Retry and plain-language errors
    let retry: String
    let retryHelp: String
    let errorNoSpeech: String
    let errorSilentMicrophone: String
    let errorInterrupted: String
    let errorRecovered: String
    let errorMissingFile: String
    let errorGeneric: String

    // MARK: First run
    let onboardingWelcomeTitle: String
    let onboardingWelcomeBody: String
    let onboardingNameTitle: String
    let onboardingNameField: String
    let onboardingNameBody: String
    let onboardingPermissionsTitle: String
    let onboardingPermissionsAsk: String
    let onboardingPermissionsWhy: String
    let onboardingPermissionsAgain: String
    let onboardingNext: String
    let onboardingNextHelp: String
    let onboardingBackHelp: String
    let onboardingStart: String
    let onboardingStartHelp: String

    // MARK: People
    let sectionPeople: String
    let peopleEmpty: String
    let peopleSearchPlaceholder: String
    let peopleSearchHelp: String
    let peopleNoMatches: String
    let personNoSelection: String
    let personNameHelp: String
    let personOrganisationPlaceholder: String
    let personOrganisationHelp: String
    let personRolePlaceholder: String
    let personRoleHelp: String
    let personNotesHeader: String
    let personNotesPlaceholder: String
    let personNotesHelp: String
    let nextConversationHeader: String
    let groupMyActions: String
    let groupTheirCommitments: String
    let groupOpenPoints: String
    let groupHooks: String
    let groupAboutPerson: String
    let groupLastDecisions: String
    let briefEmpty: String
    let briefItemHelp: String
    let personConversationsHeader: String
    let personConversationHelp: String
    let personNoConversations: String
    let noConversationYet: String
    let mergePerson: String
    let mergePersonHelp: String
    let mergeConfirmButton: String
    let linkedToPerson: String
    let saveAsPerson: String
    let unlinkPerson: String

    // MARK: Menu bar
    let menuSourceLabel: String
    let menuSourceBoth: String
    let menuSourceMicrophone: String
    let menuSourceSystem: String
    let menuStartRecording: String
    let menuStopRecording: String
    let menuConsentHint: String
    let menuYou: String
    let menuOthers: String
    let menuRecent: String
    let menuOpen: String
    let menuOpenHelp: String
    let menuOpenLorre: String
    let menuQuit: String
    let menuQuitHelp: String
    let menuRowRecording: String
    let menuRowWaiting: String
    let menuRowProcessing: String
    let menuRowReady: String
    let menuUnavailable: String
    let checkForUpdates: String
    let aboutVersionTitle: String
    let startupFailed: String
    let notifyRecoveredTitle: String
    let notifyFailedTitle: String
    let notifyReadyTitle: String
    let notifyNoSoundTitle: String

    // MARK: Units
    let hourUnit: String
    let minuteUnit: String
    let lessThanAMinute: String

    private init(_ language: LorreLanguage) {
        self.language = language
        func t(_ nl: String, _ en: String) -> String { language == .dutch ? nl : en }

        sectionToday = t("Vandaag", "Today")
        sectionConversations = t("Gesprekken", "Conversations")
        sectionPickerLabel = t("Kies een onderdeel", "Choose a section")
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
        comingUpHeader = t("Straks", "Coming up")
        calendarPrompt = t(
            "Laat Lorre in je agenda kijken, dan zie je hier wat er straks komt.",
            "Let Lorre look at your calendar to see here what is coming up."
        )
        calendarAllow = t("Agenda gebruiken", "Use calendar")
        calendarAllowHelp = t(
            "Lorre leest je agenda op deze Mac; er verlaat niets je Mac",
            "Lorre reads your calendar on this Mac; nothing leaves your Mac"
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
        tomorrowWord = t("morgen", "tomorrow")

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

        retry = t("Opnieuw proberen", "Try again")
        retryHelp = t("Werk dit gesprek opnieuw uit", "Transcribe this conversation again")
        errorNoSpeech = t(
            "Er is geen spraak gevonden in deze opname. Stond het geluid aan? Neem het gesprek dan opnieuw op.",
            "No speech was found in this recording. Was the sound on? If not, record the conversation again."
        )
        errorSilentMicrophone = t(
            "Lorre hoort geen geluid van de microfoon. Geef Lorre toestemming in Systeeminstellingen onder Privacy en beveiliging > Microfoon (zet het uit en weer aan als het al aanstaat) en begin daarna een nieuwe opname.",
            "Lorre is not hearing any sound from the microphone. Allow Lorre in System Settings under Privacy & Security > Microphone (switch it off and on again if it is already on), then start a new recording."
        )
        errorInterrupted = t(
            "De opname werd onderbroken, bijvoorbeeld doordat Lorre werd afgesloten of de Mac opnieuw opstartte. Wat al was opgenomen is bewaard. Kies Opnieuw proberen om het uit te werken.",
            "The recording was interrupted, for example because Lorre was closed or the Mac restarted. What was already recorded is saved. Choose Try again to transcribe it."
        )
        errorRecovered = t(
            "Een onderbroken opname is teruggevonden. Wat al was opgenomen is bewaard en wordt nu uitgewerkt.",
            "An interrupted recording was found again. What was already recorded is saved and is being transcribed now."
        )
        errorMissingFile = t(
            "Het geluid van dit gesprek ontbreekt of kan niet worden gelezen. Probeer het nog eens. Lukt het niet, neem het gesprek dan opnieuw op.",
            "The sound of this conversation is missing or cannot be read. Try again. If that does not work, record the conversation again."
        )
        errorGeneric = t(
            "Er ging iets mis. Probeer het nog eens. Lukt het weer niet, start Lorre dan opnieuw op.",
            "Something went wrong. Try again. If it fails again, restart Lorre."
        )

        onboardingWelcomeTitle = t("Welkom bij Lorre", "Welcome to Lorre")
        onboardingWelcomeBody = t(
            "Lorre neemt een gesprek op deze Mac op, schrijft uit wat er gezegd is en laat jou goedkeuren wat er is afgesproken. Er gaat niets van je Mac af.",
            "Lorre records a conversation on this Mac, writes out what was said, and lets you approve what was agreed. Nothing leaves your Mac."
        )
        onboardingNameTitle = t("Hoe heet je?", "What is your name?")
        onboardingNameField = t("Je naam", "Your name")
        onboardingNameBody = t(
            "Zo komt jouw naam te staan bij wat jij zelf zegt in een gesprek.",
            "This is the name that goes with your own words in a conversation."
        )
        onboardingPermissionsTitle = t("Toestemming van je Mac", "Permission from your Mac")
        onboardingPermissionsAsk = t(
            "De eerste keer dat je opneemt, vraagt macOS om toegang tot de microfoon en om het geluid van de computer op te nemen.",
            "The first time you record, macOS asks for access to the microphone and to record the sound of the computer."
        )
        onboardingPermissionsWhy = t(
            "Allebei zijn nodig: de microfoon voor jouw stem, het geluid van de computer voor de andere kant van een online gesprek.",
            "Both are needed: the microphone for your voice, the sound of the computer for the other side of an online call."
        )
        onboardingPermissionsAgain = t(
            "Na een update kan macOS de vraag opnieuw stellen. Kies dan weer om het toe te staan.",
            "After an update macOS may ask again. Just allow it again."
        )
        onboardingNext = t("Volgende", "Next")
        onboardingNextHelp = t("Ga naar de volgende stap", "Go to the next step")
        onboardingBackHelp = t("Ga terug naar de vorige stap", "Go back to the previous step")
        onboardingStart = t("Aan de slag", "Get started")
        onboardingStartHelp = t("Sluit dit scherm en begin met Lorre", "Close this screen and start using Lorre")

        sectionPeople = t("Mensen", "People")
        peopleEmpty = t(
            "Hier verschijnen de mensen met wie je spreekt. Geef bij een gesprek een spreker een naam en bewaar die als persoon, dan staat die hier.",
            "The people you talk to appear here. Give a speaker in a conversation a name and save them as a person, and they show up here."
        )
        peopleSearchPlaceholder = t("Zoek een persoon", "Search for a person")
        peopleSearchHelp = t("Zoek op naam, organisatie of functie", "Search by name, organisation or role")
        peopleNoMatches = t("Niemand gevonden.", "Nobody found.")
        personNoSelection = t(
            "Kies links een persoon om je op het volgende gesprek voor te bereiden.",
            "Pick a person on the left to prepare for the next conversation."
        )
        personNameHelp = t("Klik om de naam aan te passen", "Click to change the name")
        personOrganisationPlaceholder = t("Organisatie", "Organisation")
        personOrganisationHelp = t("Bij welke organisatie hoort deze persoon?", "Which organisation does this person belong to?")
        personRolePlaceholder = t("Functie", "Role")
        personRoleHelp = t("Wat is de functie van deze persoon?", "What is this person's role?")
        personNotesHeader = t("Aantekeningen", "Notes")
        personNotesPlaceholder = t("Schrijf hier wat je over deze persoon wilt onthouden", "Write down what you want to remember about this person")
        personNotesHelp = t("Je eigen aantekeningen over deze persoon", "Your own notes about this person")
        nextConversationHeader = t("Voor het volgende gesprek", "For the next conversation")
        groupMyActions = t("Wat ik nog moet doen", "What I still have to do")
        groupTheirCommitments = t("Wat zij hebben beloofd", "What they promised")
        groupOpenPoints = t("Openstaande punten", "Open points")
        groupHooks = t("Hierop terugkomen", "To come back to")
        groupAboutPerson = t("Over deze persoon", "About this person")
        groupLastDecisions = t("Laatst besloten", "Decided last time")
        briefEmpty = t(
            "Er staat niets open met deze persoon. Na het nakijken van een gesprek verschijnt hier wat je moet onthouden.",
            "Nothing is open with this person. After you review a conversation, what you need to remember shows up here."
        )
        briefItemHelp = t("Open het gesprek waar dit uit komt", "Open the conversation this came from")
        personConversationsHeader = t("Gesprekken", "Conversations")
        personConversationHelp = t("Open dit gesprek", "Open this conversation")
        personNoConversations = t("Nog geen gesprekken met deze persoon.", "No conversations with this person yet.")
        noConversationYet = t("Nog geen gesprek", "No conversation yet")
        mergePerson = t("Voeg samen met…", "Merge with…")
        mergePersonHelp = t(
            "Voeg deze persoon samen met iemand anders, bijvoorbeeld als dezelfde persoon er twee keer in staat",
            "Merge this person with someone else, for example when the same person is in the list twice"
        )
        mergeConfirmButton = t("Voeg samen", "Merge")
        linkedToPerson = t("Staat in je lijst met mensen", "Is in your list of people")
        saveAsPerson = t("Bewaar als persoon", "Save as person")
        unlinkPerson = t("Koppeling verwijderen", "Remove link")

        menuSourceLabel = t("Wat neem je op?", "What do you record?")
        menuSourceBoth = t("Microfoon en geluid van de computer", "Microphone and computer sound")
        menuSourceMicrophone = t("Alleen de microfoon", "Microphone only")
        menuSourceSystem = t("Alleen geluid van de computer", "Computer sound only")
        menuStartRecording = t("Opname starten", "Start recording")
        menuStopRecording = t("Opname stoppen", "Stop recording")
        menuConsentHint = t(
            "Laat de ander weten dat het gesprek wordt opgenomen.",
            "Let the other person know the conversation is being recorded."
        )
        menuYou = t("Jij", "You")
        menuOthers = t("De anderen", "Others")
        menuRecent = t("Recent", "Recent")
        menuOpen = t("Openen", "Open")
        menuOpenHelp = t("Open het uitgewerkte gesprek", "Open the written-out conversation")
        menuOpenLorre = t("Lorre openen", "Open Lorre")
        menuQuit = t("Afsluiten", "Quit")
        menuQuitHelp = t("Stop eerst de opname.", "Stop the recording first.")
        menuRowRecording = t("Wordt opgenomen…", "Recording…")
        menuRowWaiting = t("Wacht om uitgewerkt te worden", "Waiting to be written out")
        menuRowProcessing = t("Wordt uitgewerkt…", "Being written out…")
        menuRowReady = t("Klaar", "Ready")
        menuUnavailable = t("Opnemen is nu niet beschikbaar.", "Recording is not available right now.")
        checkForUpdates = t("Zoek naar updates…", "Check for Updates…")
        aboutVersionTitle = t("Versie", "Version")
        startupFailed = t(
            "Lorre kan je gesprekken nu niet openen. Sluit Lorre af en open het opnieuw. Blijft dit gebeuren, start dan je Mac opnieuw op.",
            "Lorre cannot open your conversations right now. Quit Lorre and open it again. If this keeps happening, restart your Mac."
        )
        notifyRecoveredTitle = t("Opname teruggevonden", "Recording found again")
        notifyFailedTitle = t("Uitwerken is niet gelukt", "Writing it out did not work")
        notifyReadyTitle = t("Je gesprek is klaar", "Your conversation is ready")
        notifyNoSoundTitle = t("Geen geluid van de microfoon", "No sound from the microphone")

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

    /// "2 open punten met Anna".
    func openItemsWith(_ n: Int, _ name: String) -> String {
        switch (language, n) {
        case (.dutch, 1): "1 open punt met \(name)"
        case (.dutch, _): "\(n) open punten met \(name)"
        case (.english, 1): "1 open item with \(name)"
        case (.english, _): "\(n) open items with \(name)"
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

    func onboardingStepCounter(_ step: Int, of total: Int) -> String {
        switch language {
        case .dutch: "Stap \(step) van \(total)"
        case .english: "Step \(step) of \(total)"
        }
    }

    func conversationCount(_ n: Int) -> String {
        switch (language, n) {
        case (.dutch, 1): "1 gesprek"
        case (.dutch, _): "\(n) gesprekken"
        case (.english, 1): "1 conversation"
        case (.english, _): "\(n) conversations"
        }
    }

    func openItemCount(_ n: Int) -> String {
        switch (language, n) {
        case (.dutch, 1): "1 open punt"
        case (.dutch, _): "\(n) open punten"
        case (.english, 1): "1 open item"
        case (.english, _): "\(n) open items"
        }
    }

    func lastConversationOn(_ day: String) -> String {
        switch language {
        case .dutch: "Laatst gesproken op \(day)"
        case .english: "Last spoke on \(day)"
        }
    }

    func mergeConfirmTitle(from: String, into: String) -> String {
        switch language {
        case .dutch: "“\(from)” samenvoegen met “\(into)”?"
        case .english: "Merge “\(from)” into “\(into)”?"
        }
    }

    func mergeConfirmMessage(from: String, into: String) -> String {
        switch language {
        case .dutch: "“\(from)” verdwijnt uit je lijst. Alle gesprekken en afspraken van die persoon komen bij “\(into)” te staan. Dit kun je niet terugdraaien."
        case .english: "“\(from)” disappears from your list. All conversations and agreements of that person move to “\(into)”. This cannot be undone."
        }
    }

    func thisIsPerson(_ name: String) -> String {
        switch language {
        case .dutch: "Dit is \(name)"
        case .english: "This is \(name)"
        }
    }

    func viewPerson(_ name: String) -> String {
        switch language {
        case .dutch: "Bekijk \(name)"
        case .english: "View \(name)"
        }
    }

    /// The status of a finished conversation in the menu bar, for example "Klaar · 12 min".
    func menuReadyLine(minutes: Int?) -> String {
        guard let minutes else { return menuRowReady }
        return "\(menuRowReady) · \(minutes) \(minuteUnit)"
    }

    /// Spoken by VoiceOver next to the running clock.
    func menuElapsedLabel(_ clock: String) -> String {
        switch language {
        case .dutch: "Opgenomen: \(clock)"
        case .english: "Recorded: \(clock)"
        }
    }

    func playFrom(_ clock: String) -> String {
        switch language {
        case .dutch: "Beluister vanaf \(clock)"
        case .english: "Listen from \(clock)"
        }
    }
}
