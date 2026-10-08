import AppKit
import Foundation

/// Turning prompts into inserted text: plain clicks, ⌥-click with the clipboard,
/// ⇧-click stacking, and the fill-in form for `{{placeholders}}`.
extension ShelfModel {
    struct Filling: Equatable {
        let promptIDs: [Prompt.ID]
        let title: String
        let template: String
        let fields: [String]
        let clipboard: String?
        var values: [String: String] = [:]

        var renderedText: String {
            PromptTemplate.render(template, values: values, clipboard: clipboard)
        }
    }

    /// A click on a card. ⇧ adds it to the stack, ⌥ inserts it with the clipboard.
    func activate(_ prompt: Prompt, modifiers: NSEvent.ModifierFlags) {
        errorMessage = nil
        if modifiers.contains(.shift) {
            toggleStacked(prompt)
        } else {
            use([prompt], withClipboard: modifiers.contains(.option))
        }
    }

    func toggleStacked(_ prompt: Prompt) {
        if let index = stackedIDs.firstIndex(of: prompt.id) {
            stackedIDs.remove(at: index)
        } else {
            stackedIDs.append(prompt.id)
        }
    }

    var stackedPrompts: [Prompt] {
        stackedIDs.compactMap { id in store.prompts.first { $0.id == id } }
    }

    func insertStack() {
        use(stackedPrompts)
    }

    /// Inserts the prompts (joined), asking for placeholder values first if needed.
    func use(_ prompts: [Prompt], withClipboard: Bool = false) {
        guard !prompts.isEmpty else { return }
        var template = PromptTemplate.combine(prompts.map(\.body))
        var clipboard: String?

        if withClipboard || PromptTemplate.usesClipboard(template) {
            guard let text = actions.readClipboard(), !text.isEmpty else {
                errorMessage = "The clipboard doesn't contain any text."
                return
            }
            clipboard = text
            if withClipboard { template = PromptTemplate.attachingClipboard(text, to: template) }
        }

        let fields = PromptTemplate.fields(in: template)
        let ids = prompts.map(\.id)
        guard fields.isEmpty else {
            filling = Filling(
                promptIDs: ids,
                title: prompts.count == 1 ? prompts[0].title : "\(prompts.count) prompts",
                template: template,
                fields: fields,
                clipboard: clipboard
            )
            actions.takeFocus()
            return
        }
        finishInsertion(PromptTemplate.render(template, values: [:], clipboard: clipboard), ids: ids)
    }

    func completeFilling() {
        guard let filling else { return }
        self.filling = nil
        finishInsertion(filling.renderedText, ids: filling.promptIDs)
    }

    func cancelFilling() {
        filling = nil
        actions.releaseFocus()
    }

    func copy(_ prompt: Prompt) {
        actions.copyText(prompt.body, [prompt.id])
    }

    /// Briefly highlights a prompt that just arrived on the shelf.
    func announceAdded(_ id: Prompt.ID) {
        query = ""
        selectedID = id
        recentlyAddedID = id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if recentlyAddedID == id { recentlyAddedID = nil }
        }
    }

    /// Saves text dropped onto the shelf, ignoring a card dragged out and back in.
    func receiveDrop(_ text: String) {
        if let dragged = store.prompts.first(where: { $0.id == draggedPromptID }),
           dragged.body == text.trimmingCharacters(in: .whitespacesAndNewlines) {
            return
        }
        actions.save(text)
    }

    func handleWhileFilling(_ command: Command) -> Bool {
        switch command {
        case .primary, .secondary: completeFilling()
        case .cancel: cancelFilling()
        case .close: actions.close()
        default: return false
        }
        return true
    }

    private func finishInsertion(_ text: String, ids: [Prompt.ID]) {
        if Set(ids) == Set(stackedIDs) { stackedIDs = [] }
        actions.insertText(text, ids)
        flashedIDs.formUnion(ids)
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            flashedIDs.subtract(ids)
        }
    }
}
