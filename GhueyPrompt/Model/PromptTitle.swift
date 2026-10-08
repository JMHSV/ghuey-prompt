import Foundation

enum PromptTitle {
    static let maxLength = 60

    /// Derives a short title from a prompt body: its first non-empty line,
    /// without Markdown heading/list markers, truncated on a word boundary.
    static func derive(from body: String) -> String {
        let firstLine = body
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""

        let unmarked = firstLine
            .replacingOccurrences(of: #"^(#{1,6}\s+|[-*>]\s+)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        guard unmarked.count > maxLength else { return unmarked.isEmpty ? "Untitled Prompt" : unmarked }

        let cut = unmarked.prefix(maxLength)
        let wordBoundary = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return wordBoundary.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }
}
