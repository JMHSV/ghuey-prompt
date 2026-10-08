import Foundation

/// Creating and editing prompts in the shelf's editor, and renaming in place.
extension ShelfModel {
    struct Draft: Equatable {
        let promptID: Prompt.ID?
        var title: String
        var body: String
        private let original: (title: String, body: String)

        init(prompt: Prompt?) {
            promptID = prompt?.id
            title = prompt?.title ?? ""
            body = prompt?.body ?? ""
            original = (title, body)
        }

        var isNew: Bool { promptID == nil }
        var hasChanges: Bool { title != original.title || body != original.body }

        static func == (lhs: Draft, rhs: Draft) -> Bool {
            lhs.promptID == rhs.promptID && lhs.title == rhs.title && lhs.body == rhs.body
        }
    }

    func beginEditing(_ prompt: Prompt?) {
        renamingID = nil
        filling = nil
        isDiscardArmed = false
        draft = Draft(prompt: prompt)
        actions.takeFocus()
    }

    func saveDraft() {
        guard let draft else { return }
        do {
            if let id = draft.promptID {
                try store.update(id: id, title: draft.title, body: draft.body)
                selectedID = id
            } else {
                let prompt = switch try store.save(text: draft.body, title: draft.title) {
                case let .created(prompt), let .alreadySaved(prompt): prompt
                }
                announceAdded(prompt.id)
                actions.promptCreated(prompt)
            }
            finishEditing()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Esc leaves the editor; if there are unsaved changes the first press only warns.
    func cancelEditing() {
        guard let draft else { return }
        if draft.hasChanges && !isDiscardArmed {
            isDiscardArmed = true
            return
        }
        finishEditing()
    }

    func beginRenaming(_ prompt: Prompt) {
        renamingID = prompt.id
        renameText = prompt.title
        actions.takeFocus()
    }

    func commitRename() {
        guard let id = renamingID else { return }
        perform { try store.rename(id: id, to: renameText) }
        renamingID = nil
        actions.releaseFocus()
    }

    func cancelRename() {
        renamingID = nil
        actions.releaseFocus()
    }

    /// Uses the latest saved body, even if the card that opened the menu is outdated.
    func regenerateTitle(for id: Prompt.ID) async {
        guard !generatingTitleIDs.contains(id) else { return }
        guard let prompt = store.prompts.first(where: { $0.id == id }) else {
            errorMessage = StoreError.notFound.localizedDescription
            return
        }
        generatingTitleIDs.insert(id)
        defer { generatingTitleIDs.remove(id) }
        errorMessage = nil
        do {
            let title = try await generateTitle(prompt.body)
            if try !store.applyGeneratedTitle(title, to: prompt) {
                errorMessage = "The prompt changed while its title was being generated. Try again."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleWhileEditing(_ command: Command) -> Bool {
        switch command {
        case .secondary: saveDraft()
        case .cancel: cancelEditing()
        case .close: actions.close()
        default: return false
        }
        return true
    }

    func handleWhileRenaming(_ command: Command) -> Bool {
        switch command {
        case .primary: commitRename()
        case .cancel: cancelRename()
        default: return false
        }
        return true
    }

    private func finishEditing() {
        draft = nil
        isDiscardArmed = false
        actions.releaseFocus()
    }
}
