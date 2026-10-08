import SwiftUI

/// Marks where search terms occur in card text.
enum SearchHighlight {
    static func text(_ string: String, terms: [String]) -> AttributedString {
        var text = AttributedString(string)
        for range in PromptSearch.matchRanges(of: terms, in: string) {
            guard let attributed = Range(range, in: text) else { continue }
            text[attributed].foregroundColor = .primary
            text[attributed].backgroundColor = Color.accentColor.opacity(0.28)
        }
        return text
    }

    /// The body flattened onto one line, skipping a first line that repeats the title.
    /// When searching, it starts shortly before the first match so the match is visible.
    static func excerpt(of prompt: Prompt, terms: [String]) -> String {
        let lines = prompt.body.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let repeatsTitle = lines.first.map { PromptTitle.derive(from: $0) == prompt.title } ?? false
        let flat = lines.dropFirst(repeatsTitle ? 1 : 0).filter { !$0.isEmpty }.joined(separator: " ")

        guard let first = PromptSearch.matchRanges(of: terms, in: flat).map(\.lowerBound).min(),
              flat.distance(from: flat.startIndex, to: first) > leadIn * 2 else { return flat }
        var start = flat.index(first, offsetBy: -leadIn)
        // Begin at a word boundary.
        if let space = flat[start..<first].firstIndex(of: " ") { start = flat.index(after: space) }
        return "…" + flat[start...]
    }

    private static let leadIn = 30
}
