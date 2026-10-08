import Foundation

/// Instant deletion with a few seconds to undo, instead of a confirmation step.
extension ShelfModel {
    struct Deletion: Equatable {
        let prompt: Prompt
        let index: Int
    }

    static let undoWindow: Duration = .seconds(6)

    func delete(_ prompt: Prompt) {
        guard let index = store.prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        let visibleIndex = results.firstIndex { $0.id == prompt.id }
        do {
            try store.delete(id: prompt.id)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        stackedIDs.removeAll { $0 == prompt.id }
        recentlyDeleted = Deletion(prompt: prompt, index: index)

        // Keep the cursor in place: select the neighbor that slid into this row.
        let remaining = results
        if let visibleIndex, !remaining.isEmpty {
            selectedID = remaining[min(visibleIndex, remaining.count - 1)].id
        }

        undoExpiry?.cancel()
        undoExpiry = Task {
            try? await Task.sleep(for: Self.undoWindow)
            if !Task.isCancelled { recentlyDeleted = nil }
        }
    }

    func undoDeletion() {
        guard let deletion = recentlyDeleted else { return }
        undoExpiry?.cancel()
        recentlyDeleted = nil
        perform { try store.restore(deletion.prompt, at: deletion.index) }
        selectedID = deletion.prompt.id
    }
}
