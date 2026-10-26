import Foundation

/// Jaro-Winkler string similarity — the standard for short-token fuzzy matching
/// (spell correction, name matching). Returns a score in [0, 1]; 1.0 = identical.
///
/// Pure functions, no state, no Foundation dependencies beyond `String`.
enum JaroWinkler {
    /// Jaro similarity (the base metric Winkler extends).
    static func jaro(_ left: String, _ right: String) -> Double {
        let leftChars = Array(left)
        let rightChars = Array(right)
        let leftCount = leftChars.count
        let rightCount = rightChars.count
        guard leftCount > 0, rightCount > 0 else {
            return leftCount == rightCount ? 1.0 : 0.0
        }
        // Match window: floor(max(|left|,|right|) / 2) - 1. Same definition as the
        // original Winkler paper.
        let window = max(0, max(leftCount, rightCount) / 2 - 1)
        var leftMatched = Array(repeating: false, count: leftCount)
        var rightMatched = Array(repeating: false, count: rightCount)
        var matches = 0

        for leftIdx in 0..<leftCount {
            let start = max(0, leftIdx - window)
            let end = min(leftIdx + window + 1, rightCount)
            for rightIdx in start..<end where !rightMatched[rightIdx] {
                if leftChars[leftIdx] == rightChars[rightIdx] {
                    leftMatched[leftIdx] = true
                    rightMatched[rightIdx] = true
                    matches += 1
                    break
                }
            }
        }
        guard matches > 0 else { return 0.0 }

        // Count transpositions: paired matches in different order.
        var transpositions = 0
        var rightCursor = 0
        for leftIdx in 0..<leftCount where leftMatched[leftIdx] {
            while !rightMatched[rightCursor] { rightCursor += 1 }
            if leftChars[leftIdx] != rightChars[rightCursor] { transpositions += 1 }
            rightCursor += 1
        }
        let halfTranspositions = Double(transpositions) / 2.0
        let matchCount = Double(matches)
        return (matchCount / Double(leftCount)
                + matchCount / Double(rightCount)
                + (matchCount - halfTranspositions) / matchCount) / 3.0
    }

    /// Winkler's prefix bonus: boosts strings that share a common prefix (up to
    /// 4 chars), which is usually a strong signal for typos at the end.
    static func similarity(_ left: String, _ right: String) -> Double {
        let base = jaro(left, right)
        let leftChars = Array(left)
        let rightChars = Array(right)
        let maxPrefix = min(4, min(leftChars.count, rightChars.count))
        var commonPrefix = 0
        for pos in 0..<maxPrefix where leftChars[pos] == rightChars[pos] {
            commonPrefix += 1
        }
        // Winkler's scaling factor p = 0.1 is the standard.
        return base + Double(commonPrefix) * 0.1 * (1.0 - base)
    }
}
