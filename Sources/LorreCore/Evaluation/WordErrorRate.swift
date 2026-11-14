import Foundation

/// Turns free text into the list of words that word error rate compares.
/// Lowercases, treats punctuation and hyphens as separators, drops apostrophes inside a word
/// ("zo'n" becomes "zon", "it's" becomes "its"), collapses whitespace. Digits stay as they are:
/// "3,5" becomes "3" and "5", and "twee" never equals "2". Reference and hypothesis go through
/// the same function, so the choices only need to be consistent.
public enum TextNormalizer {
    public static func words(_ text: String, foldDiacritics: Bool = false) -> [String] {
        var source = text
        if foldDiacritics {
            source = source.folding(options: [.diacriticInsensitive], locale: nil)
        }
        var words: [String] = []
        var current = String.UnicodeScalarView()
        func flush() {
            if !current.isEmpty {
                words.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        for scalar in source.lowercased().unicodeScalars {
            if scalar == "'" || scalar == "\u{2019}" || scalar == "\u{2018}" || scalar == "\u{02BC}" {
                continue
            }
            if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar) {
                current.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return words
    }
}

public struct WordErrorRate: Equatable, Sendable {
    public var substitutions: Int
    public var deletions: Int
    public var insertions: Int
    public var referenceWords: Int

    public init(substitutions: Int, deletions: Int, insertions: Int, referenceWords: Int) {
        self.substitutions = substitutions
        self.deletions = deletions
        self.insertions = insertions
        self.referenceWords = referenceWords
    }

    public var errors: Int { substitutions + deletions + insertions }

    /// (S+D+I)/N. Zero when both sides are empty; with an empty reference the insertions are divided by 1.
    public var rate: Double {
        Double(errors) / Double(max(referenceWords, 1))
    }

    /// Levenshtein alignment on words. Time O(N*M); memory O(M): the error counts travel with the
    /// cost through two rows instead of a backtrace matrix, so 20k words need no 400M-cell table.
    /// On equal cost a match or substitution wins over a deletion, which wins over an insertion.
    public static func compute(reference: [String], hypothesis: [String]) -> WordErrorRate {
        let n = reference.count
        let m = hypothesis.count
        if n == 0 { return WordErrorRate(substitutions: 0, deletions: 0, insertions: m, referenceWords: 0) }
        if m == 0 { return WordErrorRate(substitutions: 0, deletions: n, insertions: 0, referenceWords: n) }

        // Intern words so the inner loop compares integers.
        var ids: [String: Int32] = [:]
        func id(_ word: String) -> Int32 {
            if let existing = ids[word] { return existing }
            let next = Int32(ids.count)
            ids[word] = next
            return next
        }
        let ref = reference.map(id)
        let hyp = hypothesis.map(id)

        struct Cell { var cost: Int32; var sub: Int32; var del: Int32; var ins: Int32 }
        var previous = [Cell](repeating: Cell(cost: 0, sub: 0, del: 0, ins: 0), count: m + 1)
        var current = previous
        for j in 0...m { previous[j] = Cell(cost: Int32(j), sub: 0, del: 0, ins: Int32(j)) }

        for i in 1...n {
            current[0] = Cell(cost: Int32(i), sub: 0, del: Int32(i), ins: 0)
            let r = ref[i - 1]
            for j in 1...m {
                let diagonal = previous[j - 1]
                let up = previous[j]
                let left = current[j - 1]
                let match = r == hyp[j - 1]
                let diagonalCost = diagonal.cost + (match ? 0 : 1)
                let upCost = up.cost + 1
                let leftCost = left.cost + 1
                if diagonalCost <= upCost && diagonalCost <= leftCost {
                    current[j] = Cell(cost: diagonalCost, sub: diagonal.sub + (match ? 0 : 1), del: diagonal.del, ins: diagonal.ins)
                } else if upCost <= leftCost {
                    current[j] = Cell(cost: upCost, sub: up.sub, del: up.del + 1, ins: up.ins)
                } else {
                    current[j] = Cell(cost: leftCost, sub: left.sub, del: left.del, ins: left.ins + 1)
                }
            }
            swap(&previous, &current)
        }
        let last = previous[m]
        return WordErrorRate(
            substitutions: Int(last.sub), deletions: Int(last.del), insertions: Int(last.ins), referenceWords: n
        )
    }

    /// Pools several results: the total errors over the total reference words.
    public static func pooled(_ results: [WordErrorRate]) -> WordErrorRate {
        WordErrorRate(
            substitutions: results.reduce(0) { $0 + $1.substitutions },
            deletions: results.reduce(0) { $0 + $1.deletions },
            insertions: results.reduce(0) { $0 + $1.insertions },
            referenceWords: results.reduce(0) { $0 + $1.referenceWords }
        )
    }
}
