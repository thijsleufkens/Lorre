import XCTest
@testable import LorreCore

/// Answers with canned strings and remembers what it was asked.
final class FakeTextGenerator: TextGenerator, @unchecked Sendable {
    typealias Handler = @Sendable (_ call: Int, _ system: String, _ prompt: String) throws -> String

    let identifier = "fake:model"
    private let handler: Handler
    private let recorded = NSLockedBox()

    init(_ handler: @escaping Handler) { self.handler = handler }

    var calls: [(system: String, prompt: String, json: Bool)] { recorded.all() }

    func generate(system: String, prompt: String, json: Bool) async throws -> String {
        let call = recorded.append((system, prompt, json))
        return try handler(call, system, prompt)
    }
}

final class NSLockedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(system: String, prompt: String, json: Bool)] = []

    /// Returns the index of the new entry.
    func append(_ item: (system: String, prompt: String, json: Bool)) -> Int {
        lock.withLock {
            items.append(item)
            return items.count - 1
        }
    }

    func all() -> [(system: String, prompt: String, json: Bool)] { lock.withLock { items } }
}

final class TwoStepOutcomeProposerTests: XCTestCase {
    private let conversationId = UUID()
    private var me: Participant!
    private var anna: Participant!
    private var segments: [Segment] = []

    override func setUp() {
        me = Participant(conversationId: conversationId, name: "Thijs", isUser: true)
        anna = Participant(conversationId: conversationId, name: "Anna de Vries")
        let version = UUID()
        func segment(_ seconds: Int, _ participant: Participant, _ text: String) -> Segment {
            Segment(transcriptVersionId: version, participantId: participant.id,
                    startMs: seconds * 1000, endMs: seconds * 1000 + 3000, text: text)
        }
        segments = [
            segment(0, me, "Hoi Anna."),
            segment(100, anna, "Ik geef je naam door aan Jimmy."),
            segment(200, me, "Ik stuur je de offerte."),
            segment(310, anna, "Dan bellen we dinsdag."),
            segment(400, me, "Ik kom niet naar het event."),
            segment(700, anna, "Fijn gesprek."),
        ]
    }

    private func input(language: LorreLanguage = .dutch, segments: [Segment]? = nil) -> ProposalInput {
        ProposalInput(type: .network, language: language, participants: [me, anna], segments: segments ?? self.segments)
    }

    private func proposer(_ generator: FakeTextGenerator, chunkSeconds: Int = 300, cap: Int = 5) -> TwoStepOutcomeProposer {
        TwoStepOutcomeProposer(generator: generator, chunkSeconds: chunkSeconds, maxInformationItems: cap)
    }

    // MARK: Chunking

    func testChunksCutOnSegmentBoundaries() {
        let chunks = TwoStepOutcomeProposer.chunks(segments, chunkSeconds: 300)
        XCTAssertEqual(chunks.map { chunk in chunk.map { $0.startMs / 1000 } }, [[0, 100, 200], [310, 400], [700]])
        XCTAssertEqual(chunks.flatMap { $0 }, segments)
    }

    func testOneRequestPerChunkPlusOneConsolidation() async throws {
        let generator = FakeTextGenerator { call, _, _ in
            call < 3 ? #"{"items":[{"kind":"decision","summary":"Besluit \#(call).","lines":[1]}]}"# : #"{"items":[]}"#
        }
        _ = try await proposer(generator).propose(input())
        XCTAssertEqual(generator.calls.count, 4)
        XCTAssertTrue(generator.calls.allSatisfy(\.json))
    }

    func testPromptShowsNumberedLinesWithNames() async throws {
        let generator = FakeTextGenerator { _, _, _ in #"{"items":[]}"# }
        _ = try await proposer(generator).propose(input())
        let first = try XCTUnwrap(generator.calls.first?.prompt)
        XCTAssertTrue(first.contains("[1] Thijs: Hoi Anna."))
        XCTAssertTrue(first.contains("[3] Thijs: Ik stuur je de offerte."))
        XCTAssertTrue(first.contains("[2] Anna de Vries: Ik geef je naam door aan Jimmy."))
        XCTAssertFalse(first.contains("Dan bellen we dinsdag."), "second chunk leaked into the first request")
    }

    func testEnglishPromptsAreEnglish() async throws {
        let generator = FakeTextGenerator { _, _, _ in #"{"items":[]}"# }
        _ = try await proposer(generator).propose(input(language: .english))
        XCTAssertTrue(try XCTUnwrap(generator.calls.first?.prompt).contains("Conversation type"))
    }

    // MARK: Step 1

    func testCandidatesWithBadLineNumbersAreDropped() async throws {
        let generator = FakeTextGenerator { call, _, _ in
            if call == 0 {
                return """
                {"items":[
                 {"kind":"decision","summary":"Geldig.","lines":[2]},
                 {"kind":"decision","summary":"Regel bestaat niet.","lines":[99]},
                 {"kind":"decision","summary":"Nul.","lines":[0]},
                 {"kind":"decision","summary":"Geen regels.","lines":[]},
                 {"kind":"decision","summary":"Ontbrekend."},
                 {"kind":"decision","lines":[1]},
                 {"summary":"Geen soort.","lines":[1]},
                 {"kind":"gossip","summary":"Onbekende soort.","lines":[1]}
                ]}
                """
            }
            return #"{"items":[]}"#
        }
        let result = try await proposer(generator, chunkSeconds: 10_000).propose(input())
        // Step 2 returned nothing usable, so the step-1 candidates come back.
        XCTAssertEqual(result.map(\.text), ["Geldig."])
        XCTAssertEqual(result.first?.evidenceSegmentIds, [segments[1].id])
    }

    func testEvidenceIsAlwaysASubsetOfTheRealSegments() async throws {
        let generator = FakeTextGenerator { call, _, _ in
            switch call {
            case 0: #"{"items":[{"kind":"myAction","summary":"A.","owner":"ik","lines":[3,"1",2.0,77]}]}"#
            case 1: #"{"items":[{"kind":"decision","summary":"B.","lines":[1,5]}]}"#
            default: #"{"items":[{"kind":"myAction","summary":"A merged.","owner":"Thijs","candidates":[1,2,42]}]}"#
            }
        }
        let result = try await proposer(generator).propose(input())
        let real = Set(segments.map(\.id))
        XCTAssertFalse(result.isEmpty)
        for outcome in result {
            XCTAssertFalse(outcome.evidenceSegmentIds.isEmpty)
            XCTAssertTrue(Set(outcome.evidenceSegmentIds).isSubset(of: real))
        }
        // Evidence is ordered like the transcript.
        let ids = try XCTUnwrap(result.first).evidenceSegmentIds
        XCTAssertEqual(ids, segments.filter { ids.contains($0.id) }.map(\.id))
    }

    func testNoCandidatesMeansNoSecondRequest() async throws {
        let generator = FakeTextGenerator { _, _, _ in "Er is niets." }
        let result = try await proposer(generator).propose(input())
        XCTAssertEqual(result, [])
        XCTAssertEqual(generator.calls.count, 3, "one per chunk (three), none for consolidation")
    }

    func testEmptyTranscriptAsksNothing() async throws {
        let generator = FakeTextGenerator { _, _, _ in XCTFail("no request expected"); return "" }
        let result = try await proposer(generator).propose(input(segments: []))
        XCTAssertEqual(result, [])
    }

    // MARK: Step 2

    func testConsolidationMergesAndFixesKind() async throws {
        let generator = FakeTextGenerator { call, _, prompt in
            if call == 0 {
                return """
                {"items":[
                 {"kind":"theirCommitment","summary":"Anna geeft de naam door aan Jimmy.","owner":"Anna de Vries","lines":[2]},
                 {"kind":"openPoint","summary":"De naam gaat naar Jimmy.","lines":[2,3]},
                 {"kind":"information","summary":"Offerte volgt.","lines":[3]}
                ]}
                """
            }
            XCTAssertFalse(prompt.contains("Ik geef je naam door"), "step 2 must not see the transcript")
            XCTAssertTrue(prompt.contains("[1] theirCommitment | eigenaar: Anna de Vries | Anna geeft de naam door aan Jimmy."))
            return """
            {"items":[
             {"kind":"theirCommitment","summary":"Anna geeft de naam van Thijs door aan Jimmy.","owner":"anna de vries","candidates":[1,2]},
             {"kind":"myAction","summary":"Thijs stuurt de offerte.","owner":"ik","candidates":[3]}
            ]}
            """
        }
        let result = try await proposer(generator, chunkSeconds: 10_000).propose(input())
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].kind, .theirCommitment)
        XCTAssertEqual(result[0].ownerParticipantId, anna.id)
        XCTAssertEqual(result[0].evidenceSegmentIds, [segments[1].id, segments[2].id])
        XCTAssertEqual(result[1].kind, .myAction, "information was re-kinded to an action")
        XCTAssertEqual(result[1].ownerParticipantId, me.id)
        XCTAssertEqual(result[1].evidenceSegmentIds, [segments[2].id])
    }

    func testFallbackToCandidatesWhenConsolidationIsGarbage() async throws {
        for garbage in ["dit is geen json", "{\"items\": [", #"{"items":[{"kind":"decision","summary":"x","candidates":[9]}]}"#, #"{"items":[]}"#] {
            let generator = FakeTextGenerator { call, _, _ in
                call == 0
                    ? #"{"items":[{"kind":"decision","summary":"Zelfde.","lines":[1]},{"kind":"decision","summary":" zelfde. ","lines":[2]},{"kind":"openPoint","summary":"Anders.","lines":[3]}]}"#
                    : garbage
            }
            let result = try await proposer(generator, chunkSeconds: 10_000).propose(input())
            XCTAssertEqual(result.map(\.text), ["Zelfde.", "Anders."], "garbage: \(garbage)")
            XCTAssertEqual(result.first?.evidenceSegmentIds, [segments[0].id])
        }
    }

    func testFallbackWhenConsolidationRequestFails() async throws {
        struct Boom: Error {}
        let generator = FakeTextGenerator { call, _, _ in
            if call == 0 { return #"{"items":[{"kind":"decision","summary":"Blijft.","lines":[1]}]}"# }
            throw Boom()
        }
        let result = try await proposer(generator, chunkSeconds: 10_000).propose(input())
        XCTAssertEqual(result.map(\.text), ["Blijft."])
    }

    func testStepOneFailureIsPropagated() async {
        struct Boom: Error {}
        let generator = FakeTextGenerator { _, _, _ in throw Boom() }
        do {
            _ = try await proposer(generator).propose(input())
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }

    // MARK: Tolerant parsing

    func testCodeFencesAndSurroundingProseAreTolerated() async throws {
        let generator = FakeTextGenerator { call, _, _ in
            if call == 0 {
                return """
                Natuurlijk, hier is de lijst:
                ```json
                {"items":[{"kind":"DECISION","summary":"Niet naar het event.","owner":null,"lines":[5],"confidence":0.9}],"note":"x"}
                ```
                Succes!
                """
            }
            return "Zeker!\n```\n[{\"kind\":\"decision\",\"summary\":\"Thijs komt niet naar het event.\",\"candidates\":[1],\"extra\":true}]\n```"
        }
        let result = try await proposer(generator, chunkSeconds: 10_000).propose(input())
        XCTAssertEqual(result.map(\.text), ["Thijs komt niet naar het event."])
        XCTAssertEqual(result.first?.kind, .decision)
        XCTAssertNil(result.first?.ownerParticipantId)
    }

    func testOwnerMapping() async throws {
        let generator = FakeTextGenerator { call, _, _ in
            if call == 0 {
                return """
                {"items":[
                 {"kind":"myAction","summary":"Een.","owner":"IK","lines":[1]},
                 {"kind":"theirCommitment","summary":"Twee.","owner":"ANNA DE VRIES","lines":[2]},
                 {"kind":"theirCommitment","summary":"Drie.","owner":"anna","lines":[2]},
                 {"kind":"theirCommitment","summary":"Vier.","owner":"Onbekende Persoon","lines":[2]},
                 {"kind":"myAction","summary":"Vijf.","owner":null,"lines":[3]},
                 {"kind":"decision","summary":"Zes.","owner":"Thijs","lines":[4]},
                 {"kind":"myAction","summary":"Zeven.","owner":"me","lines":[5]},
                 {"kind":"myAction","summary":"Acht.","owner":"I","lines":[5]}
                ]}
                """
            }
            return "kapot"
        }
        let result = try await proposer(generator, chunkSeconds: 10_000).propose(input())
        let owners = Dictionary(uniqueKeysWithValues: result.map { ($0.text, $0.ownerParticipantId) })
        XCTAssertEqual(owners["Een."], me.id)
        XCTAssertEqual(owners["Twee."], anna.id)
        XCTAssertEqual(owners["Drie."], anna.id)
        XCTAssertEqual(owners["Vier."] ?? nil, nil)
        XCTAssertEqual(owners["Vijf."] ?? nil, nil)
        XCTAssertEqual(owners["Zes."] ?? nil, nil, "a decision has no owner")
        XCTAssertEqual(owners["Zeven."], me.id)
        XCTAssertEqual(owners["Acht."], me.id)
    }

    func testInformationIsCappedKeepingTheFirst() async throws {
        let items = (1...8).map { #"{"kind":"information","summary":"Feit \#($0).","lines":[1]}"# }.joined(separator: ",")
        let generator = FakeTextGenerator { call, _, _ in
            call == 0 ? #"{"items":[\#(items),{"kind":"decision","summary":"Besluit.","lines":[2]}]}"# : "kapot"
        }
        let result = try await proposer(generator, chunkSeconds: 10_000, cap: 5).propose(input())
        XCTAssertEqual(result.filter { $0.kind == .information }.map(\.text), (1...5).map { "Feit \($0)." })
        XCTAssertEqual(result.filter { $0.kind == .decision }.count, 1)
    }

    func testInformationCapDefaultIsFive() {
        XCTAssertEqual(TwoStepOutcomeProposer(generator: FakeTextGenerator { _, _, _ in "" }).maxInformationItems, 5)
        XCTAssertEqual(TwoStepOutcomeProposer(generator: FakeTextGenerator { _, _, _ in "" }).chunkSeconds, 300)
    }

    func testIdentifierNamesTheGenerator() {
        XCTAssertEqual(TwoStepOutcomeProposer(generator: FakeTextGenerator { _, _, _ in "" }).identifier, "two-step/fake:model")
    }
}
