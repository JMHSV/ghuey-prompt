import Foundation

enum PromptMerge {
    /// Combines two libraries (e.g. this Mac's and one already in iCloud Drive).
    /// Prompts present in both keep the most recently edited version, plus the
    /// usage history of both copies. Text saved separately on both sides is kept once.
    static func merge(_ local: [Prompt], _ other: [Prompt]) -> [Prompt] {
        var merged = local
        for incoming in other {
            guard let index = merged.firstIndex(where: { $0.id == incoming.id }) else {
                if !merged.contains(where: { $0.body == incoming.body }) { merged.append(incoming) }
                continue
            }
            let existing = merged[index]
            var winner = incoming.updatedAt > existing.updatedAt ? incoming : existing
            winner.useCount = max(existing.useCount, incoming.useCount)
            winner.lastUsedAt = [existing.lastUsedAt, incoming.lastUsedAt].compactMap { $0 }.max()
            winner.lastUsedByApp = existing.lastUsedByApp.merging(incoming.lastUsedByApp) { max($0, $1) }
            merged[index] = winner
        }
        return merged
    }
}
