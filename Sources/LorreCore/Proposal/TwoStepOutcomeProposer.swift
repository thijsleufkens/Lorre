import Foundation

/// Finds candidate outcomes per chunk of the transcript, then consolidates the candidates in one
/// request. The second step never sees the transcript and refers to candidates by number, so the
/// evidence of an outcome is always carried over from step 1 and cannot be invented.
public struct TwoStepOutcomeProposer: OutcomeProposer {
    public let generator: any TextGenerator
    public let chunkSeconds: Int
    /// The experiment drowned in facts: at most this many `information` items are kept.
    public let maxInformationItems: Int

    public var identifier: String { "two-step/\(generator.identifier)" }

    public init(generator: any TextGenerator, chunkSeconds: Int = 300, maxInformationItems: Int = 5) {
        self.generator = generator
        self.chunkSeconds = max(1, chunkSeconds)
        self.maxInformationItems = max(0, maxInformationItems)
    }

    /// A step-1 result: what was found and where.
    struct Candidate: Equatable {
        var kind: OutcomeKind
        var text: String
        var ownerName: String?
        /// Segment ids in transcript order; never empty.
        var segmentIds: [UUID]
        /// Position of the first segment in the input, to keep the final order chronological.
        var order: Int
    }

    public func propose(_ input: ProposalInput) async throws -> [ProposedOutcome] {
        let segments = input.segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !segments.isEmpty else { return [] }
        let order = Dictionary(uniqueKeysWithValues: segments.enumerated().map { ($1.id, $0) })
        let names = Dictionary(uniqueKeysWithValues: input.participants.map { ($0.id, $0.name) })
        let participantsLine = Self.participantsLine(input.participants, language: input.language)
        let matcher = ParticipantMatcher(participants: input.participants)

        // Step 1
        var candidates: [Candidate] = []
        for chunk in Self.chunks(segments, chunkSeconds: chunkSeconds) {
            try Task.checkCancellation()
            let lines = chunk.enumerated().map { index, segment in
                let speaker = segment.participantId.flatMap { names[$0] }
                    ?? (input.language == .dutch ? "Onbekend" : "Unknown")
                return "[\(index + 1)] \(speaker): \(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            let answer = try await generator.generate(
                system: ProposalPrompts.candidateSystem(input.language),
                prompt: ProposalPrompts.candidatePrompt(
                    language: input.language, type: input.type, participantsLine: participantsLine, lines: lines
                ),
                json: true
            )
            candidates += Self.parseCandidates(answer, chunk: chunk, order: order)
        }
        guard !candidates.isEmpty else { return [] }

        // Step 2
        var result: [Candidate]
        if let consolidated = try await consolidate(
            candidates, input: input, participantsLine: participantsLine
        ) {
            result = consolidated
        } else {
            result = Self.removeExactDuplicates(candidates)
        }
        result.sort { $0.order < $1.order }

        var informationSeen = 0
        return result.compactMap { candidate in
            if candidate.kind == .information {
                informationSeen += 1
                if informationSeen > maxInformationItems { return nil }
            }
            return ProposedOutcome(
                kind: candidate.kind,
                text: candidate.text,
                ownerParticipantId: Self.owner(of: candidate, matcher: matcher, participants: input.participants),
                evidenceSegmentIds: candidate.segmentIds
            )
        }
    }

    /// The owner the model named, with two safe fallbacks: my action is mine, and somebody
    /// else's commitment belongs to the other person when there is only one.
    static func owner(of candidate: Candidate, matcher: ParticipantMatcher, participants: [Participant]) -> UUID? {
        guard candidate.kind.hasOwner else { return nil }
        let user = participants.first(where: \.isUser)
        let named = matcher.match(candidate.ownerName)
        switch candidate.kind {
        case .myAction:
            return user?.id ?? named
        case .theirCommitment:
            if let named, named != user?.id { return named }
            let others = participants.filter { !$0.isUser }
            return others.count == 1 ? others[0].id : nil
        default:
            return named
        }
    }

    // MARK: Chunking

    /// Cuts on segment boundaries: a new chunk starts with the first segment that begins at least
    /// `chunkSeconds` after the first segment of the current chunk.
    static func chunks(_ segments: [Segment], chunkSeconds: Int) -> [[Segment]] {
        var chunks: [[Segment]] = []
        var current: [Segment] = []
        for segment in segments {
            if let first = current.first, segment.startMs - first.startMs >= chunkSeconds * 1000 {
                chunks.append(current)
                current = []
            }
            current.append(segment)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    static func participantsLine(_ participants: [Participant], language: LorreLanguage) -> String {
        guard !participants.isEmpty else { return language == .dutch ? "onbekend" : "unknown" }
        return participants.map { participant in
            guard participant.isUser else { return participant.name }
            return language == .dutch
                ? "\(participant.name) (de gebruiker; \"ik\" in het gesprek)"
                : "\(participant.name) (the user; \"I\" in the conversation)"
        }.joined(separator: ", ") + (language == .dutch
            ? ". Gebruik in je zinnen precies deze namen; schrijf nooit \"de gebruiker\" en vertaal de namen niet"
            : ". Use exactly these names in your sentences; never write \"the user\" and do not translate the names")
    }

    // MARK: Step 1 parsing

    static func parseCandidates(_ answer: String, chunk: [Segment], order: [UUID: Int]) -> [Candidate] {
        guard let items = ProposalParsing.items(from: ProposalParsing.jsonValue(in: answer)) else { return [] }
        return items.compactMap { item in
            guard let kind = ProposalParsing.kind(item),
                  let text = ProposalParsing.string(item, ["summary", "text", "samenvatting"]) else { return nil }
            let numbers = Set(ProposalParsing.numbers(item, ["lines", "line_numbers", "regels"]))
                .filter { $0 >= 1 && $0 <= chunk.count }
                .sorted()
            guard !numbers.isEmpty else { return nil }
            let segments = numbers.map { chunk[$0 - 1] }
            let owner = ProposalParsing.ownerName(item).flatMap { $0 }
            return Candidate(
                kind: kind,
                text: text,
                ownerName: kind.hasOwner ? owner : nil,
                segmentIds: segments.map(\.id),
                order: segments.compactMap { order[$0.id] }.min() ?? 0
            )
        }
    }

    // MARK: Step 2

    /// nil when the step failed or answered with something unusable; the caller then falls back.
    private func consolidate(
        _ candidates: [Candidate],
        input: ProposalInput,
        participantsLine: String
    ) async throws -> [Candidate]? {
        let listed = candidates.enumerated().map { index, candidate in
            let owner = candidate.ownerName.map { " | \(input.language == .dutch ? "eigenaar" : "owner"): \($0)" } ?? ""
            return "[\(index + 1)] \(candidate.kind.rawValue)\(owner) | \(candidate.text)"
        }
        let answer: String
        do {
            answer = try await generator.generate(
                system: ProposalPrompts.consolidationSystem(input.language),
                prompt: ProposalPrompts.consolidationPrompt(
                    language: input.language, type: input.type,
                    participantsLine: participantsLine, candidates: listed
                ),
                json: true
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        return Self.parseConsolidation(answer, candidates: candidates, segments: input.segments)
    }

    static func parseConsolidation(_ answer: String, candidates: [Candidate], segments: [Segment]) -> [Candidate]? {
        guard let items = ProposalParsing.items(from: ProposalParsing.jsonValue(in: answer)) else { return nil }
        let position = Dictionary(uniqueKeysWithValues: segments.enumerated().map { ($1.id, $0) })
        var result: [Candidate] = []
        for item in items {
            guard let kind = ProposalParsing.kind(item) else { continue }
            let numbers = Set(ProposalParsing.numbers(item, ["candidates", "kandidaten", "from", "sources"]))
                .filter { $0 >= 1 && $0 <= candidates.count }
                .sorted()
            guard !numbers.isEmpty else { continue }
            let sources = numbers.map { candidates[$0 - 1] }
            let ids = Set(sources.flatMap(\.segmentIds))
                .sorted { (position[$0] ?? 0) < (position[$1] ?? 0) }
            let text = ProposalParsing.string(item, ["summary", "text", "samenvatting"]) ?? sources[0].text
            let owner: String? = switch ProposalParsing.ownerName(item) {
            case .some(let value): value
            case .none: sources.first(where: { $0.ownerName != nil })?.ownerName
            }
            result.append(Candidate(
                kind: kind,
                text: text,
                ownerName: kind.hasOwner ? owner : nil,
                segmentIds: ids,
                order: sources.map(\.order).min() ?? 0
            ))
        }
        // An answer that drops everything is more likely a failed step than a verdict.
        return result.isEmpty ? nil : result
    }

    static func removeExactDuplicates(_ candidates: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert(ProposalParsing.fold($0.text)).inserted }
    }
}
