import Foundation

/// A hand-made answer key for one conversation. See `docs/eval.md`.
public struct EvalReference: Codable, Equatable, Sendable {
    public struct Expected: Codable, Equatable, Sendable {
        public var kind: String
        public var owner: String?
        public var keywords: [String]
        public var label: String?

        public init(kind: String, owner: String? = nil, keywords: [String], label: String? = nil) {
            self.kind = kind
            self.owner = owner
            self.keywords = keywords
            self.label = label
        }

        public var title: String { label ?? keywords.joined(separator: " ") }
    }

    public var conversationId: String
    public var expected: [Expected]

    public init(conversationId: String, expected: [Expected]) {
        self.conversationId = conversationId
        self.expected = expected
    }

    public enum ValidationError: Error, Equatable, LocalizedError {
        case unknownKind(String)
        case noKeywords(String)

        public var errorDescription: String? {
            switch self {
            case .unknownKind(let kind):
                "Unknown kind \"\(kind)\" in the reference. Use one of: \(OutcomeKind.allCases.map(\.rawValue).joined(separator: ", "))."
            case .noKeywords(let title):
                "The expected item \"\(title)\" has no keywords."
            }
        }
    }

    public static func load(from data: Data) throws -> EvalReference {
        let reference = try JSONDecoder().decode(EvalReference.self, from: data)
        for item in reference.expected {
            guard OutcomeKind(rawValue: item.kind) != nil else { throw ValidationError.unknownKind(item.kind) }
            guard item.keywords.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                throw ValidationError.noKeywords(item.title)
            }
        }
        return reference
    }
}

public struct EvalItemResult: Equatable, Sendable, Codable {
    public var label: String
    public var kind: String
    public var owner: String?
    /// Some proposal contains all keywords.
    public var found: Bool
    /// Some proposal that contains all keywords also has the right kind and owner.
    public var correct: Bool

    public init(label: String, kind: String, owner: String?, found: Bool, correct: Bool) {
        self.label = label
        self.kind = kind
        self.owner = owner
        self.found = found
        self.correct = correct
    }
}

public struct EvalReport: Equatable, Sendable, Codable {
    public var items: [EvalItemResult]
    public var proposalCount: Int
    /// Proposals that contain the keywords of no expected item.
    public var unmatchedProposalCount: Int

    public init(items: [EvalItemResult], proposalCount: Int, unmatchedProposalCount: Int) {
        self.items = items
        self.proposalCount = proposalCount
        self.unmatchedProposalCount = unmatchedProposalCount
    }

    public var foundCount: Int { items.filter(\.found).count }
    public var correctCount: Int { items.filter(\.correct).count }
    public var recallFound: Double { items.isEmpty ? 0 : Double(foundCount) / Double(items.count) }
    public var recallCorrect: Double { items.isEmpty ? 0 : Double(correctCount) / Double(items.count) }
}

public enum ProposalEvaluator {
    public static func score(
        reference: EvalReference,
        proposals: [ProposedOutcome],
        participants: [Participant]
    ) -> EvalReport {
        let texts = proposals.map { ProposalParsing.fold($0.text) }
        let matcher = ParticipantMatcher(participants: participants)

        func containsAll(_ text: String, _ expected: EvalReference.Expected) -> Bool {
            let keywords = expected.keywords.map(ProposalParsing.fold).filter { !$0.isEmpty }
            return !keywords.isEmpty && keywords.allSatisfy { text.contains($0) }
        }

        func ownerMatches(_ proposal: ProposedOutcome, _ expected: EvalReference.Expected) -> Bool {
            guard let name = expected.owner?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                return proposal.ownerParticipantId == nil
            }
            guard let wanted = matcher.match(name), let actual = proposal.ownerParticipantId else { return false }
            return wanted == actual
        }

        var matchedProposals = Set<Int>()
        let items = reference.expected.map { expected -> EvalItemResult in
            let hits = texts.indices.filter { containsAll(texts[$0], expected) }
            matchedProposals.formUnion(hits)
            let correct = hits.contains { index in
                proposals[index].kind.rawValue == expected.kind && ownerMatches(proposals[index], expected)
            }
            return EvalItemResult(
                label: expected.title, kind: expected.kind, owner: expected.owner,
                found: !hits.isEmpty, correct: correct
            )
        }
        return EvalReport(
            items: items,
            proposalCount: proposals.count,
            unmatchedProposalCount: proposals.count - matchedProposals.count
        )
    }
}
