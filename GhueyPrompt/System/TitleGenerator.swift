import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes short titles for saved prompts with Apple's on-device model (macOS 26+,
/// Apple Intelligence enabled). Private and offline; unavailable elsewhere.
enum TitleGenerator {
    enum GenerationError: LocalizedError {
        case unavailable
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unavailable: "Title generation requires macOS 26 or later with Apple Intelligence enabled."
            case .invalidResponse: "Couldn't generate a title. Try again."
            }
        }
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    /// Returns a short title, surfacing unavailability and generation failures.
    static func title(for body: String) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), SystemLanguageModel.default.isAvailable else {
            throw GenerationError.unavailable
        }
        let session = LanguageModelSession(instructions: """
            You name prompts that a person saved to reuse with AI assistants. \
            Reply with only a title of 2 to 6 words in Title Case that says what the prompt asks for. \
            No quotes, no trailing punctuation.
            """)
        let response = try await session.respond(to: "Prompt:\n\(body.prefix(2_000))")
        guard let title = sanitize(response.content) else { throw GenerationError.invalidResponse }
        return title
        #else
        throw GenerationError.unavailable
        #endif
    }

    /// Turns the model's reply into a title, or nil if it isn't usable as one.
    static func sanitize(_ raw: String) -> String? {
        let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let cleaned = firstLine
            .replacingOccurrences(of: #"^\s*[Tt]itle:\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'“”‘’*#.:")))
        guard !cleaned.isEmpty, cleaned.count <= PromptTitle.maxLength else { return nil }
        return cleaned
    }
}
