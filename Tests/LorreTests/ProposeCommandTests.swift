import ArgumentParser
import XCTest
import LorreCore
@testable import Lorre

final class ProposeCommandTests: XCTestCase {
    func testBothCommandsAreRegisteredAndRouted() {
        let registered = Set(LorreCLI.configuration.subcommands.compactMap { $0.configuration.commandName })
        for name in ["propose", "eval"] {
            XCTAssertTrue(registered.contains(name), "\(name) is not registered in LorreCLI")
            XCTAssertTrue(CLIRouting.subcommands.contains(name), "\(name) is not routed")
            XCTAssertTrue(CLIRouting.isCLIInvocation(["/path/Lorre", name]))
        }
    }

    func testProposeParsesItsOptions() throws {
        let command = try ProposeCommand.parse(["ABC123", "--model", "qwen3.5:9b", "--dry-run", "--root", "/tmp/x"])
        XCTAssertEqual(command.id, "ABC123")
        XCTAssertEqual(command.proposer.model, "qwen3.5:9b")
        XCTAssertTrue(command.dryRun)
        XCTAssertEqual(command.store.root, "/tmp/x")
        XCTAssertEqual(try ProposeCommand.parse(["ABC"]).proposer.model, "gemma4:e4b")
        XCTAssertFalse(try ProposeCommand.parse(["ABC"]).dryRun)
    }

    func testEvalParsesItsOptions() throws {
        let command = try EvalCommand.parse(["ref.json", "--json", "--model", "m", "--root", "/tmp/x"])
        XCTAssertEqual(command.reference, "ref.json")
        XCTAssertTrue(command.json)
        XCTAssertEqual(command.proposer.model, "m")
    }

    func testRenderGroupsByKindWithOwnerAndTime() {
        let conversationId = UUID()
        let anna = LorreCore.Participant(conversationId: conversationId, name: "Anna")
        let segment = LorreCore.Segment(transcriptVersionId: UUID(), participantId: anna.id, startMs: 125_000, endMs: 130_000, text: "x")
        let text = ProposeCommand.render(
            [
                ProposedOutcome(kind: .decision, text: "Niet naar het event.", evidenceSegmentIds: [segment.id]),
                ProposedOutcome(kind: .theirCommitment, text: "Anna belt.", ownerParticipantId: anna.id, evidenceSegmentIds: [segment.id]),
            ],
            participants: [anna], segments: [segment], language: .dutch
        )
        let commitment = text.range(of: "Toezeggingen van anderen (1)")
        let decision = text.range(of: "Besluiten (1)")
        XCTAssertNotNil(commitment)
        XCTAssertNotNil(decision)
        XCTAssertTrue(commitment!.lowerBound < decision!.lowerBound, "commitments come before decisions")
        XCTAssertTrue(text.contains("- Anna belt.  [Anna, 02:05]"))
        XCTAssertTrue(text.contains("- Niet naar het event.  [02:05]"))
        XCTAssertEqual(ProposeCommand.render([], participants: [], segments: [], language: .dutch), "No proposals.")
    }

    func testEvalRenderShowsEveryNumber() throws {
        let report = EvalReport(
            items: [
                EvalItemResult(label: "a", kind: "decision", owner: nil, found: true, correct: true),
                EvalItemResult(label: "b", kind: "myAction", owner: "ik", found: true, correct: false),
                EvalItemResult(label: "c", kind: "myAction", owner: "ik", found: false, correct: false),
            ],
            proposalCount: 7, unmatchedProposalCount: 4
        )
        let text = try EvalCommand.render(report, model: "two-step/x", elapsedSeconds: 12.34, json: false)
        XCTAssertTrue(text.contains("Recall (found):   2/3  67%"))
        XCTAssertTrue(text.contains("Recall (correct): 1/3  33%"))
        XCTAssertTrue(text.contains("Proposals: 7, matching no expected item: 4"))
        XCTAssertTrue(text.contains("Elapsed: 12.3 s"))
        XCTAssertTrue(text.contains("MISSED"))

        let json = try EvalCommand.render(report, model: "two-step/x", elapsedSeconds: 1, json: true)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["proposals"] as? Int, 7)
        XCTAssertEqual(object["unmatchedProposals"] as? Int, 4)
        XCTAssertEqual((object["items"] as? [Any])?.count, 3)
    }
}
