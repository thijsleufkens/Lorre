import Foundation

public struct SpeakerTurn: Equatable, Sendable, Codable {
    public var speaker: String
    public var startMs: Int
    public var endMs: Int

    public init(speaker: String, startMs: Int, endMs: Int) {
        self.speaker = speaker
        self.startMs = startMs
        self.endMs = endMs
    }
}

/// How much reference speech lands on the right person, after matching hypothesis speakers to
/// reference speakers one-to-one. This is not DER: it ignores false alarms (speech the hypothesis
/// invents where the reference has none) and stretches where the reference has overlap.
public struct SpeakerScore: Equatable, Sendable {
    public var referenceSpeakers: Int
    public var hypothesisSpeakers: Int
    /// Reference speech time where exactly one reference speaker is active.
    public var scoredMs: Int
    /// Of that, time attributed to the mapped hypothesis speaker.
    public var correctMs: Int
    /// No hypothesis speaker at all.
    public var missedMs: Int
    /// Only other hypothesis speakers (including unmapped ones).
    public var confusedMs: Int
    public var accuracy: Double

    public init(
        referenceSpeakers: Int, hypothesisSpeakers: Int, scoredMs: Int,
        correctMs: Int, missedMs: Int, confusedMs: Int, accuracy: Double
    ) {
        self.referenceSpeakers = referenceSpeakers
        self.hypothesisSpeakers = hypothesisSpeakers
        self.scoredMs = scoredMs
        self.correctMs = correctMs
        self.missedMs = missedMs
        self.confusedMs = confusedMs
        self.accuracy = accuracy
    }

    /// Frame based: a frame of `frameMs` belongs to a turn when its midpoint lies inside the turn.
    /// Mapping: greedy one-to-one by overlap (on scored frames), largest first, ties by name.
    /// A frame is correct when the mapped speaker is among the active hypothesis speakers.
    public static func compute(reference: [SpeakerTurn], hypothesis: [SpeakerTurn], frameMs: Int = 100) -> SpeakerScore {
        let frame = max(frameMs, 1)
        let referenceTurns = reference.filter { $0.endMs > $0.startMs }
        let hypothesisTurns = hypothesis.filter { $0.endMs > $0.startMs }
        let referenceNames = Array(Set(referenceTurns.map(\.speaker))).sorted()
        let hypothesisNames = Array(Set(hypothesisTurns.map(\.speaker))).sorted()
        let referenceIndex = Dictionary(uniqueKeysWithValues: referenceNames.enumerated().map { ($1, $0) })
        let hypothesisIndex = Dictionary(uniqueKeysWithValues: hypothesisNames.enumerated().map { ($1, $0) })

        func firstFrame(atOrAfter ms: Int) -> Int {
            // smallest k with k*frame + frame/2 >= ms
            let shifted = ms - frame / 2
            return shifted <= 0 ? 0 : (shifted + frame - 1) / frame
        }
        let frameCount = max(
            referenceTurns.map { firstFrame(atOrAfter: $0.endMs) }.max() ?? 0,
            hypothesisTurns.map { firstFrame(atOrAfter: $0.endMs) }.max() ?? 0
        )
        guard frameCount > 0 else {
            return SpeakerScore(
                referenceSpeakers: referenceNames.count, hypothesisSpeakers: hypothesisNames.count,
                scoredMs: 0, correctMs: 0, missedMs: 0, confusedMs: 0, accuracy: 0
            )
        }

        var referenceCount = [Int32](repeating: 0, count: frameCount)
        var referenceWho = [Int32](repeating: -1, count: frameCount)
        for turn in referenceTurns {
            let who = Int32(referenceIndex[turn.speaker]!)
            for k in firstFrame(atOrAfter: turn.startMs)..<firstFrame(atOrAfter: turn.endMs) where k < frameCount {
                // The same speaker listed twice on a frame still counts once.
                if referenceCount[k] == 1 && referenceWho[k] == who { continue }
                referenceCount[k] += 1
                referenceWho[k] = who
            }
        }
        var hypothesisActive = [[Int32]](repeating: [], count: frameCount)
        for turn in hypothesisTurns {
            let who = Int32(hypothesisIndex[turn.speaker]!)
            for k in firstFrame(atOrAfter: turn.startMs)..<firstFrame(atOrAfter: turn.endMs) where k < frameCount {
                if !hypothesisActive[k].contains(who) { hypothesisActive[k].append(who) }
            }
        }

        // Overlap matrix on scored frames.
        var overlap = [[Int]](repeating: [Int](repeating: 0, count: hypothesisNames.count), count: referenceNames.count)
        for k in 0..<frameCount where referenceCount[k] == 1 {
            for h in hypothesisActive[k] { overlap[Int(referenceWho[k])][Int(h)] += 1 }
        }
        var candidates: [(count: Int, ref: Int, hyp: Int)] = []
        for r in 0..<referenceNames.count {
            for h in 0..<hypothesisNames.count where overlap[r][h] > 0 { candidates.append((overlap[r][h], r, h)) }
        }
        candidates.sort { ($0.count, $1.ref, $1.hyp) > ($1.count, $0.ref, $0.hyp) }
        var mapped = [Int](repeating: -1, count: referenceNames.count)   // reference -> hypothesis
        var hypothesisTaken = Set<Int>()
        for candidate in candidates where mapped[candidate.ref] < 0 && !hypothesisTaken.contains(candidate.hyp) {
            mapped[candidate.ref] = candidate.hyp
            hypothesisTaken.insert(candidate.hyp)
        }

        var scored = 0, correct = 0, missed = 0, confused = 0
        for k in 0..<frameCount where referenceCount[k] == 1 {
            scored += 1
            let active = hypothesisActive[k]
            if active.isEmpty {
                missed += 1
            } else if mapped[Int(referenceWho[k])] >= 0 && active.contains(Int32(mapped[Int(referenceWho[k])])) {
                correct += 1
            } else {
                confused += 1
            }
        }
        return SpeakerScore(
            referenceSpeakers: referenceNames.count, hypothesisSpeakers: hypothesisNames.count,
            scoredMs: scored * frame, correctMs: correct * frame, missedMs: missed * frame, confusedMs: confused * frame,
            accuracy: scored == 0 ? 0 : Double(correct) / Double(scored)
        )
    }
}
