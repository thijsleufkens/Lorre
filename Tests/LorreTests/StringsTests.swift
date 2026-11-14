import LorreCore
import XCTest
@testable import Lorre

final class StringsTests: XCTestCase {
    private func stringProperties(of strings: Strings) -> [(name: String, value: String)] {
        Mirror(reflecting: strings).children.compactMap { child in
            guard let name = child.label, let value = child.value as? String else { return nil }
            return (name, value)
        }
    }

    func testEveryTextIsFilledInBothLanguages() {
        for strings in [Strings.dutch, Strings.english] {
            let properties = stringProperties(of: strings)
            XCTAssertGreaterThan(properties.count, 80, "the Mirror should see the texts")
            for property in properties {
                XCTAssertFalse(
                    property.value.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(property.name) is empty in \(strings.language)"
                )
            }
        }
    }

    func testLanguagesDifferWhereTheyShould() {
        let dutch = Dictionary(uniqueKeysWithValues: stringProperties(of: .dutch).map { ($0.name, $0.value) })
        let english = Dictionary(uniqueKeysWithValues: stringProperties(of: .english).map { ($0.name, $0.value) })
        XCTAssertEqual(Set(dutch.keys), Set(english.keys))
        let same = dutch.keys.filter { dutch[$0] == english[$0] }
        // Words that are the same in both languages are fine, but most texts must be translated.
        XCTAssertLessThan(same.count, 12, "untranslated: \(same.sorted())")
        XCTAssertEqual(dutch["reviewButton"], "Nakijken")
        XCTAssertEqual(english["reviewButton"], "Review")
    }

    func testNoTechnicalWordsInVisibleTexts() {
        let banned = ["segment", "diarization", "diarisatie", "pipeline", "json"]
        for strings in [Strings.dutch, Strings.english] {
            for property in stringProperties(of: strings) {
                for word in banned {
                    XCTAssertFalse(
                        property.value.lowercased().contains(word),
                        "\(property.name) contains \(word)"
                    )
                }
            }
        }
    }

    func testPluralsForZeroOneAndTwo() {
        let nl = Strings.dutch
        XCTAssertEqual(nl.toReviewCount(0), "0 gesprekken na te kijken")
        XCTAssertEqual(nl.toReviewCount(1), "1 gesprek na te kijken")
        XCTAssertEqual(nl.toReviewCount(2), "2 gesprekken na te kijken")
        XCTAssertEqual(nl.proposedOutcomesLine(1), "1 voorgestelde uitkomst")
        XCTAssertEqual(nl.proposedOutcomesLine(2), "2 voorgestelde uitkomsten")
        XCTAssertEqual(nl.pendingCount(0), "Alles is beoordeeld")
        XCTAssertEqual(nl.pendingCount(1), "1 nog te beoordelen")
        XCTAssertEqual(nl.pendingCount(2), "2 nog te beoordelen")
        XCTAssertEqual(nl.selectedFragments(1), "1 stuk geselecteerd")
        XCTAssertEqual(nl.selectedFragments(2), "2 stukken geselecteerd")

        let en = Strings.english
        XCTAssertEqual(en.toReviewCount(0), "0 conversations to review")
        XCTAssertEqual(en.toReviewCount(1), "1 conversation to review")
        XCTAssertEqual(en.toReviewCount(2), "2 conversations to review")
        XCTAssertEqual(en.proposedOutcomesLine(1), "1 proposed outcome")
        XCTAssertEqual(en.proposedOutcomesLine(2), "2 proposed outcomes")
        XCTAssertEqual(en.pendingCount(0), "Everything is judged")
        XCTAssertEqual(en.pendingCount(1), "1 left to judge")
        XCTAssertEqual(en.pendingCount(2), "2 left to judge")
        XCTAssertEqual(en.selectedFragments(1), "1 part selected")
        XCTAssertEqual(en.selectedFragments(2), "2 parts selected")
    }

    func testFirstRunAndRetryTextsExistInBothLanguages() {
        XCTAssertEqual(Strings.dutch.retry, "Opnieuw proberen")
        XCTAssertEqual(Strings.english.retry, "Try again")
        XCTAssertEqual(Strings.dutch.onboardingStart, "Aan de slag")
        XCTAssertEqual(Strings.english.onboardingStart, "Get started")
        for strings in [Strings.dutch, Strings.english] {
            // The permission step is text only: it must say that macOS asks, not point at buttons.
            XCTAssertTrue(strings.onboardingPermissionsAsk.contains("macOS"))
            XCTAssertNotEqual(strings.onboardingWelcomeBody, strings.onboardingNameBody)
        }
    }

    func testTextsWithValuesInThem() {
        XCTAssertTrue(Strings.dutch.noHits(for: "prijs").contains("prijs"))
        XCTAssertTrue(Strings.english.savedAt("~/Documents/Lorre").contains("~/Documents/Lorre"))
        XCTAssertTrue(Strings.dutch.playFrom("21:26").contains("21:26"))
    }

    func testPeopleTextsAndPlurals() {
        XCTAssertEqual(Strings.dutch.sectionPeople, "Mensen")
        XCTAssertEqual(Strings.english.sectionPeople, "People")
        XCTAssertEqual(Strings.dutch.conversationCount(0), "0 gesprekken")
        XCTAssertEqual(Strings.dutch.conversationCount(1), "1 gesprek")
        XCTAssertEqual(Strings.dutch.conversationCount(2), "2 gesprekken")
        XCTAssertEqual(Strings.english.conversationCount(1), "1 conversation")
        XCTAssertEqual(Strings.english.conversationCount(2), "2 conversations")
        XCTAssertEqual(Strings.dutch.openItemCount(1), "1 open punt")
        XCTAssertEqual(Strings.dutch.openItemCount(2), "2 open punten")
        XCTAssertEqual(Strings.english.openItemCount(1), "1 open item")
        XCTAssertEqual(Strings.english.openItemCount(0), "0 open items")
        XCTAssertEqual(Strings.dutch.thisIsPerson("Anna"), "Dit is Anna")
        XCTAssertEqual(Strings.english.viewPerson("Anna"), "View Anna")
        for strings in [Strings.dutch, Strings.english] {
            XCTAssertTrue(strings.mergeConfirmTitle(from: "A", into: "B").contains("A"))
            XCTAssertTrue(strings.mergeConfirmMessage(from: "A", into: "B").contains("B"))
            XCTAssertTrue(strings.lastConversationOn("8 okt").contains("8 okt"))
        }
    }

    func testMenuBarTextsExistInBothLanguages() {
        XCTAssertEqual(Strings.dutch.menuStartRecording, "Opname starten")
        XCTAssertEqual(Strings.english.menuStartRecording, "Start recording")
        XCTAssertEqual(Strings.dutch.menuOpenLorre, "Lorre openen")
        XCTAssertEqual(Strings.dutch.menuReadyLine(minutes: 12), "Klaar · 12 min")
        XCTAssertEqual(Strings.english.menuReadyLine(minutes: 3), "Ready · 3 min")
        XCTAssertEqual(Strings.dutch.menuReadyLine(minutes: nil), "Klaar")
        XCTAssertEqual(Strings.dutch.menuElapsedLabel("01:15"), "Opgenomen: 01:15")
        XCTAssertEqual(Strings.english.menuElapsedLabel("01:15"), "Recorded: 01:15")
        XCTAssertNotEqual(Strings.dutch.notifyReadyTitle, Strings.english.notifyReadyTitle)
        XCTAssertNotEqual(Strings.dutch.startupFailed, Strings.english.startupFailed)
    }
}
