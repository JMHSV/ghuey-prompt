import Foundation

enum PromptSearch {
    /// Filters prompts to those containing every word of `query` (in title or body,
    /// ignoring case and diacritics) and orders them by match quality.
    ///
    /// With an empty query everything is listed: favorites first (in the order they
    /// were starred), then prompts used in `app` (most recent first), then the rest
    /// by recency. Ties in match quality are broken the same way.
    static func results(for query: String, in prompts: [Prompt], app: String? = nil) -> [Prompt] {
        let terms = terms(in: query)
        guard !terms.isEmpty else {
            let favorites = prompts.filter(\.isFavorite).sorted { $0.favoritedAt! < $1.favoritedAt! }
            let rest = prompts.filter { !$0.isFavorite }.sorted { isMoreRelevant($0, $1, app: app) }
            return favorites + rest
        }

        return prompts
            .compactMap { prompt in score(prompt, terms: terms).map { (prompt, $0) } }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : isMoreRelevant(lhs.0, rhs.0, app: app)
            }
            .map(\.0)
    }

    /// The search words in `query`, as matched by `results`.
    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { normalize(String($0)) }
    }

    /// Where any of `terms` occur in `text`, for highlighting.
    static func matchRanges(of terms: [String], in text: String) -> [Range<String.Index>] {
        terms.flatMap { term in
            var ranges: [Range<String.Index>] = []
            var searchStart = text.startIndex
            while let range = text.range(
                of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<text.endIndex
            ) {
                ranges.append(range)
                searchStart = range.upperBound
            }
            return ranges
        }
    }

    private static func score(_ prompt: Prompt, terms: [String]) -> Int? {
        let title = normalize(prompt.title)
        let body = normalize(prompt.body)
        var total = 0
        for term in terms {
            if title.hasPrefix(term) {
                total += 100
            } else if title.contains(" " + term) {
                total += 60
            } else if title.contains(term) {
                total += 40
            } else if body.contains(term) {
                total += 10
            } else {
                return nil
            }
        }
        return total
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Prompts used in the current app come first (most recent use there first),
    /// then everything else by overall recency.
    private static func isMoreRelevant(_ lhs: Prompt, _ rhs: Prompt, app: String?) -> Bool {
        let lhsInApp = app.flatMap { lhs.lastUsedByApp[$0] }
        let rhsInApp = app.flatMap { rhs.lastUsedByApp[$0] }
        switch (lhsInApp, rhsInApp) {
        case let (lhsDate?, rhsDate?): return lhsDate > rhsDate
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.recency > rhs.recency
        }
    }
}
