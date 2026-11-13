import Foundation

/// The languages Lorre's own texts exist in.
public enum LorreLanguage: String, CaseIterable, Sendable {
    case dutch = "nl"
    case english = "en"

    /// Dutch when it is among the user's preferred languages ahead of English, otherwise English.
    public static var current: LorreLanguage {
        preferred(from: Locale.preferredLanguages)
    }

    public static func preferred(from identifiers: [String]) -> LorreLanguage {
        for identifier in identifiers {
            let code = identifier.lowercased().prefix(2)
            if code == "nl" { return .dutch }
            if code == "en" { return .english }
        }
        return .english
    }
}

public extension OutcomeKind {
    /// The order in which kinds are shown and exported: what needs doing first.
    static let displayOrder: [OutcomeKind] = [
        .myAction, .theirCommitment, .decision, .openPoint, .followUpHook, .information, .personNote,
    ]

    /// Kinds that have someone responsible for them.
    var hasOwner: Bool { self == .myAction || self == .theirCommitment }

    func title(_ language: LorreLanguage, plural: Bool = true) -> String {
        switch (self, language, plural) {
        case (.myAction, .dutch, true): "Mijn acties"
        case (.myAction, .dutch, false): "Mijn actie"
        case (.myAction, .english, true): "My actions"
        case (.myAction, .english, false): "My action"
        case (.theirCommitment, .dutch, true): "Toezeggingen van anderen"
        case (.theirCommitment, .dutch, false): "Toezegging van een ander"
        case (.theirCommitment, .english, true): "Their commitments"
        case (.theirCommitment, .english, false): "Their commitment"
        case (.decision, .dutch, true): "Besluiten"
        case (.decision, .dutch, false): "Besluit"
        case (.decision, .english, true): "Decisions"
        case (.decision, .english, false): "Decision"
        case (.openPoint, .dutch, true): "Open punten"
        case (.openPoint, .dutch, false): "Open punt"
        case (.openPoint, .english, true): "Open points"
        case (.openPoint, .english, false): "Open point"
        case (.followUpHook, .dutch, true): "Haakjes om terug te komen"
        case (.followUpHook, .dutch, false): "Haakje om terug te komen"
        case (.followUpHook, .english, true): "Follow-up hooks"
        case (.followUpHook, .english, false): "Follow-up hook"
        case (.information, .dutch, _): "Informatie"
        case (.information, .english, _): "Information"
        case (.personNote, .dutch, true): "Over de persoon"
        case (.personNote, .dutch, false): "Notitie over de persoon"
        case (.personNote, .english, true): "About the person"
        case (.personNote, .english, false): "Note about the person"
        }
    }
}

public extension ConversationType {
    func title(_ language: LorreLanguage) -> String {
        switch (self, language) {
        case (.workMeeting, .dutch): "Werkoverleg"
        case (.workMeeting, .english): "Work meeting"
        case (.intake, _): "Intake"
        case (.network, .dutch): "Netwerkgesprek"
        case (.network, .english): "Network conversation"
        case (.other, .dutch): "Overig"
        case (.other, .english): "Other"
        }
    }
}
