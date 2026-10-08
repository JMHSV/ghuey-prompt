import Foundation

/// Fill-in placeholders written as `{{name}}`. `{{clipboard}}` is filled automatically.
enum PromptTemplate {
    static let clipboardField = "clipboard"

    private static var placeholder: Regex<(Substring, Substring)> { /\{\{\s*([^{}]+?)\s*\}\}/ }

    /// Placeholder names the user must fill, in order of first appearance.
    static func fields(in body: String) -> [String] {
        var seen = Set<String>()
        return body.matches(of: placeholder)
            .map { String($0.output.1) }
            .filter { $0.lowercased() != clipboardField && seen.insert($0).inserted }
    }

    static func usesClipboard(_ body: String) -> Bool {
        body.matches(of: placeholder).contains { $0.output.1.lowercased() == clipboardField }
    }

    /// Replaces every placeholder with its value; unfilled ones become empty.
    static func render(_ body: String, values: [String: String], clipboard: String? = nil) -> String {
        body.replacing(placeholder) { match in
            let name = String(match.output.1)
            return name.lowercased() == clipboardField ? (clipboard ?? "") : (values[name] ?? "")
        }
    }

    /// Adds clipboard contents to a prompt: at `{{clipboard}}` if present,
    /// otherwise as a fenced block after it.
    static func attachingClipboard(_ clipboard: String, to body: String) -> String {
        if usesClipboard(body) { return body }
        return body + "\n\n```\n" + clipboard.trimmingCharacters(in: .newlines) + "\n```"
    }

    /// Joins several prompts into one, in the given order.
    static func combine(_ bodies: [String]) -> String {
        bodies.joined(separator: "\n\n")
    }
}
