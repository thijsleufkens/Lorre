import Foundation

/// The texts the two-step proposer sends. The kind names inside the JSON are the raw values of
/// `OutcomeKind`; everything else is in the conversation language.
enum ProposalPrompts {
    // MARK: Step 1: candidates per chunk

    static func candidateSystem(_ language: LorreLanguage) -> String {
        switch language {
        case .dutch:
            """
            Je haalt uitkomsten uit een automatisch getranscribeerd gesprek. Het transcript bevat \
            herkenningsfouten: lees erdoorheen, maar verzin niets. Je antwoordt uitsluitend met JSON.
            """
        case .english:
            """
            You extract outcomes from an automatically transcribed conversation. The transcript contains \
            recognition errors: read through them, but invent nothing. You answer with JSON only.
            """
        }
    }

    static func candidatePrompt(
        language: LorreLanguage,
        type: ConversationType,
        participantsLine: String,
        lines: [String]
    ) -> String {
        let transcript = lines.joined(separator: "\n")
        switch language {
        case .dutch:
            return """
            Gesprekstype: \(type.title(.dutch)).
            Deelnemers: \(participantsLine).

            Hieronder staat een stuk van het gesprek met genummerde regels. Zoek de uitkomsten in dit stuk.

            Soorten uitkomsten (gebruik exact deze namen):
            - myAction: iets dat de gebruiker zelf gaat doen of heeft toegezegd.
            - theirCommitment: iets dat een ander gaat doen of heeft toegezegd.
            - decision: een besluit dat genomen is.
            - openPoint: een vraag of punt dat nog open staat.
            - followUpHook: een aanleiding om later contact op te nemen of iets op te pakken.
            - personNote: iets blijvends over de persoon zelf (rol, situatie, voorkeur) dat nuttig is om te onthouden.
            - information: een losse feitelijke mededeling. Alleen als ze echt belangrijk is; liever weglaten.

            Regels:
            - Schrijf elke uitkomst als één zin in het Nederlands, in je eigen woorden. Geen citaat en geen losse zinsdelen.
            - "owner" is de naam van degene die het doet (alleen bij myAction en theirCommitment), anders null. Gebruik de naam, niet "ik".
            - "lines" bevat de nummers van de regels waaruit de uitkomst blijkt. Gebruik alleen nummers die hieronder staan.
            - Meer is niet beter: neem alleen echte uitkomsten op. Praatjes, beleefdheden en algemene opmerkingen zijn geen uitkomst. Is er niets, geef dan een lege lijst.

            Antwoord met JSON in dit formaat:
            {"items":[{"kind":"myAction","summary":"Stuurt morgen de offerte op.","owner":"Naam","lines":[3,4]}]}

            Gesprek:
            \(transcript)
            """
        case .english:
            return """
            Conversation type: \(type.title(.english)).
            Participants: \(participantsLine).

            Below is a part of the conversation with numbered lines. Find the outcomes in this part.

            Kinds of outcome (use exactly these names):
            - myAction: something the user will do or has promised to do.
            - theirCommitment: something someone else will do or has promised.
            - decision: a decision that was made.
            - openPoint: a question or point that is still open.
            - followUpHook: a reason to get back in touch or pick something up later.
            - personNote: something lasting about the person (role, situation, preference) that is worth remembering.
            - information: a loose factual statement. Only when it really matters; leave it out when in doubt.

            Rules:
            - Write each outcome as one sentence in English, in your own words. No quotes and no sentence fragments.
            - "owner" is the name of the person who does it (only for myAction and theirCommitment), otherwise null. Use the name, not "I".
            - "lines" holds the numbers of the lines the outcome comes from. Use only numbers that appear below.
            - More is not better: include real outcomes only. Small talk, courtesies and general remarks are not outcomes. If there is nothing, return an empty list.

            Answer with JSON in this format:
            {"items":[{"kind":"myAction","summary":"Sends the quote tomorrow.","owner":"Name","lines":[3,4]}]}

            Conversation:
            \(transcript)
            """
        }
    }

    // MARK: Step 2: consolidation over the candidates

    static func consolidationSystem(_ language: LorreLanguage) -> String {
        switch language {
        case .dutch:
            """
            Je ruimt een lijst kandidaat-uitkomsten van een gesprek op. Je ziet het gesprek zelf niet, alleen de \
            kandidaten. Je antwoordt uitsluitend met JSON.
            """
        case .english:
            """
            You tidy up a list of candidate outcomes of a conversation. You do not see the conversation itself, \
            only the candidates. You answer with JSON only.
            """
        }
    }

    static func consolidationPrompt(
        language: LorreLanguage,
        type: ConversationType,
        participantsLine: String,
        candidates: [String]
    ) -> String {
        let list = candidates.joined(separator: "\n")
        switch language {
        case .dutch:
            return """
            Gesprekstype: \(type.title(.dutch)).
            Deelnemers: \(participantsLine).

            Hieronder staan genummerde kandidaat-uitkomsten, per stuk van het gesprek verzameld. Maak er de definitieve lijst van:
            - Voeg kandidaten samen die over hetzelfde gaan en noem alle nummers die erbij horen.
            - Laat weg wat geen uitkomst is: praatjes, losse feiten zonder gevolg, herhalingen, citaten.
            - Corrigeer de soort en de eigenaar als die niet kloppen. Een myAction is van de gebruiker, een theirCommitment van een ander. Alleen die twee soorten hebben een eigenaar; bij de rest is "owner" null.
            - Schrijf elke uitkomst als één duidelijke zin in het Nederlands. Verzin niets dat niet in de kandidaten staat.
            - "candidates" bevat de nummers van de kandidaten waaruit de uitkomst bestaat. Gebruik alleen nummers die hieronder staan.

            Soorten (exact deze namen): myAction, theirCommitment, decision, openPoint, followUpHook, personNote, information.

            Antwoord met JSON in dit formaat:
            {"items":[{"kind":"myAction","summary":"Stuurt morgen de offerte op.","owner":"Naam","candidates":[2,5]}]}

            Kandidaten:
            \(list)
            """
        case .english:
            return """
            Conversation type: \(type.title(.english)).
            Participants: \(participantsLine).

            Below are numbered candidate outcomes, collected per part of the conversation. Turn them into the final list:
            - Merge candidates about the same thing and name all numbers that belong to it.
            - Drop what is not an outcome: small talk, loose facts without consequence, repetitions, quotes.
            - Correct the kind and the owner when they are wrong. A myAction belongs to the user, a theirCommitment to someone else. Only these two kinds have an owner; for the others "owner" is null.
            - Write each outcome as one clear sentence in English. Invent nothing that is not in the candidates.
            - "candidates" holds the numbers of the candidates the outcome is made of. Use only numbers that appear below.

            Kinds (exactly these names): myAction, theirCommitment, decision, openPoint, followUpHook, personNote, information.

            Answer with JSON in this format:
            {"items":[{"kind":"myAction","summary":"Sends the quote tomorrow.","owner":"Name","candidates":[2,5]}]}

            Candidates:
            \(list)
            """
        }
    }
}
