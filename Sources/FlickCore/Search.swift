import Foundation

/// Typed-text filtering of the switcher: every character of the query must appear in order (case and accents
/// ignored); contiguous runs and word starts score higher.
public enum FuzzySearch {
    static func normalize(_ s: String) -> [Character] {
        Array(s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil))
    }

    /// Higher is better; nil when the query doesn't match.
    public static func score(query: String, in text: String) -> Int? {
        let q = normalize(query).filter { !$0.isWhitespace }
        guard !q.isEmpty else { return 0 }
        let t = normalize(text)
        var score = 0
        var qi = 0
        var previousMatch = -2
        var firstMatch = -1
        for (ti, c) in t.enumerated() where qi < q.count {
            guard c == q[qi] else { continue }
            var bonus = 1
            if ti == previousMatch + 1 { bonus += 5 }
            if ti == 0 || !(t[ti - 1].isLetter || t[ti - 1].isNumber) { bonus += 8 }
            score += bonus
            if firstMatch < 0 { firstMatch = ti }
            previousMatch = ti
            qi += 1
        }
        guard qi == q.count else { return nil }
        // Prefer whole-substring matches, matches near the start, then shorter texts.
        if t.count >= q.count, String(t).contains(String(q)) { score += 20 }
        return score * 100 - min(firstMatch * 4, 80) - min(t.count, 19)
    }

    /// Keeps the matching entries, best first; equal scores keep their original order.
    public static func filter(_ entries: [SwitcherEntry], query: String) -> [SwitcherEntry] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return entries }
        return entries.enumerated()
            .compactMap { index, entry -> (Int, Int, SwitcherEntry)? in
                let text = entry.window != nil ? "\(entry.appName) \(entry.title)" : entry.appName
                return score(query: query, in: text).map { ($0, index, entry) }
            }
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
            .map(\.2)
    }
}
