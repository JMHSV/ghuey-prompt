import Foundation
import Observation

/// Owns the prompt collection and persists it as human-readable JSON.
@MainActor
@Observable
final class PromptStore {
    enum SaveOutcome: Equatable {
        case created(Prompt)
        case alreadySaved(Prompt)
    }

    private(set) var prompts: [Prompt] = []
    private(set) var fileURL: URL
    /// What we last read or wrote, so our own writes don't count as external changes.
    @ObservationIgnored private var lastSyncedData: Data?

    /// Loads prompts from `fileURL`. A missing file means an empty library;
    /// an unreadable one throws so the caller can surface it instead of overwriting data.
    init(fileURL: URL) throws {
        self.fileURL = fileURL
        prompts = try Self.read(fileURL) ?? []
        lastSyncedData = try? Data(contentsOf: fileURL)
    }

    // MARK: Saving and editing

    /// Saves `text` as a new prompt, unless an identical prompt already exists.
    @discardableResult
    func save(text: String, title: String? = nil) throws -> SaveOutcome {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw StoreError.emptyPrompt }

        if let existing = prompts.first(where: { $0.body == body }) {
            return .alreadySaved(existing)
        }
        let prompt = Prompt(title: Self.resolvedTitle(title, body: body), body: body)
        try commit(prompts + [prompt])
        return .created(prompt)
    }

    func update(id: Prompt.ID, title: String, body: String) throws {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { throw StoreError.emptyPrompt }
        try modify(id) { prompt in
            prompt.title = Self.resolvedTitle(title, body: trimmedBody)
            prompt.body = trimmedBody
            prompt.updatedAt = .now
        }
    }

    func rename(id: Prompt.ID, to title: String) throws {
        try modify(id) { prompt in
            prompt.title = Self.resolvedTitle(title, body: prompt.body)
            prompt.updatedAt = .now
        }
    }

    /// Replaces an automatically derived title with a better one, unless the
    /// user renamed the prompt in the meantime.
    func applyGeneratedTitle(_ title: String, to id: Prompt.ID, replacing expected: String) throws {
        guard prompts.first(where: { $0.id == id })?.title == expected else { return }
        try modify(id) { $0.title = title }
    }

    func setFavorite(id: Prompt.ID, _ isFavorite: Bool) throws {
        try modify(id) { $0.favoritedAt = isFavorite ? .now : nil }
    }

    /// Records that the prompt was inserted, optionally into a specific app.
    func recordUse(id: Prompt.ID, in app: String?) throws {
        try modify(id) { prompt in
            prompt.lastUsedAt = .now
            prompt.useCount += 1
            if let app { prompt.lastUsedByApp[app] = .now }
        }
    }

    func delete(id: Prompt.ID) throws {
        try commit(prompts.filter { $0.id != id })
    }

    /// Puts a deleted prompt back where it was (for undo).
    func restore(_ prompt: Prompt, at index: Int) throws {
        guard !prompts.contains(where: { $0.id == prompt.id }) else { return }
        var restored = prompts
        restored.insert(prompt, at: min(index, restored.count))
        try commit(restored)
    }

    // MARK: Syncing with the file

    /// Picks up changes made outside the app (another Mac via iCloud, a text editor).
    /// A file that has gone missing is ignored rather than read as "no prompts", so a
    /// sync hiccup can't empty the library; the next save writes it back.
    /// Returns whether anything changed.
    @discardableResult
    func reloadFromDisk() throws -> Bool {
        let data = try? Data(contentsOf: fileURL)
        guard data != lastSyncedData, let reloaded = try Self.read(fileURL) else { return false }
        prompts = reloaded
        lastSyncedData = data
        return true
    }

    /// Moves the library to `newURL`, merging with any library already there.
    func relocate(to newURL: URL) throws {
        guard newURL.standardizedFileURL != fileURL.standardizedFileURL else { return }
        let existing = try Self.read(newURL) ?? []
        let merged = PromptMerge.merge(prompts, existing)
        let oldURL = fileURL
        fileURL = newURL
        do {
            try commit(merged)
        } catch {
            fileURL = oldURL
            throw error
        }
    }

    // MARK: Persistence

    private func modify(_ id: Prompt.ID, _ change: (inout Prompt) -> Void) throws {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound }
        var updated = prompts
        change(&updated[index])
        try commit(updated)
    }

    /// Writes first, then publishes, so memory never diverges from disk.
    private func commit(_ newPrompts: [Prompt]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(newPrompts)
        try data.write(to: fileURL, options: .atomic)
        lastSyncedData = data
        prompts = newPrompts
    }

    private static func read(_ url: URL) throws -> [Prompt]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode([Prompt].self, from: Data(contentsOf: url))
    }

    private static func resolvedTitle(_ title: String?, body: String) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? PromptTitle.derive(from: body) : trimmed
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum StoreError: LocalizedError {
    case emptyPrompt
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyPrompt: "A prompt can't be empty."
        case .notFound: "That prompt no longer exists."
        }
    }
}
