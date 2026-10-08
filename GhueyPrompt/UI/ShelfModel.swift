import AppKit
import Foundation
import Observation

/// State and keyboard behavior of the shelf. Behavior lives in focused extensions:
/// insertion (`+Insertion`), editing and renaming (`+Editing`), deletion (`+Deletion`).
@MainActor
@Observable
final class ShelfModel {
    /// Keyboard intents, independent of the physical shortcut that triggers them.
    enum Command {
        case moveUp, moveDown
        case primary      // ↩  insert / confirm
        case secondary    // ⌘↩ copy / save
        case cancel       // esc
        case newPrompt    // ⌘N
        case edit         // ⌘E
        case delete       // ⌘⌫
        case undo         // ⌘Z
        case favorite     // ⌘D
        case close        // ⌘W
    }

    struct Actions {
        /// Types text into the app the user was working in.
        var insertText: (String, [Prompt.ID]) -> Void
        var copyText: (String, [Prompt.ID]) -> Void
        var readClipboard: () -> String?
        var save: (String) -> Void
        /// A prompt was created in the shelf's editor.
        var promptCreated: (Prompt) -> Void
        var setPinned: (Bool) -> Void
        /// Gives the shelf keyboard focus (for typing into it).
        var takeFocus: () -> Void
        /// Hands keyboard focus back to the app the user was typing in.
        var releaseFocus: () -> Void
        /// Esc with nothing left to clear: closes a temporary shelf, unfocuses a pinned one.
        var dismiss: () -> Void
        var close: () -> Void
        /// Shows (or with nil, hides) the full-text preview beside a card whose
        /// frame is given in the shelf's SwiftUI global space.
        var preview: (Prompt?, CGRect) -> Void
    }

    let store: PromptStore
    var actions: Actions = .none

    // Browsing
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            selectedID = results.first?.id
        }
    }
    var selectedID: Prompt.ID?
    /// Bundle identifier of the app the shelf was opened over; ranks its prompts first.
    private(set) var app: String?
    /// Set by the window controller; drives the pin button.
    var isPinned = false
    /// Bumped whenever cards should play their entrance animation.
    private(set) var presentationID = 0
    /// Bumped when the search field should take focus.
    private(set) var searchFocusRequest = 0
    /// Browse order captured when the order last settled; see `results`.
    @ObservationIgnored private var settledOrder: [Prompt.ID: Int] = [:]

    // Insertion (see +Insertion)
    var stackedIDs: [Prompt.ID] = []
    var filling: Filling?
    var flashedIDs: Set<Prompt.ID> = []
    var recentlyAddedID: Prompt.ID?
    /// The prompt being dragged out of the shelf, so dropping it back is a no-op.
    var draggedPromptID: Prompt.ID?

    // Editing (see +Editing)
    var draft: Draft?
    var isDiscardArmed = false
    var renamingID: Prompt.ID?
    var renameText = ""

    // Deletion (see +Deletion)
    var recentlyDeleted: Deletion?
    @ObservationIgnored var undoExpiry: Task<Void, Never>?

    var errorMessage: String?

    init(store: PromptStore) {
        self.store = store
    }

    /// What the shelf lists. While browsing (no search) the order stays put until
    /// `settleOrder()`, so a card never jumps away from under the pointer right after
    /// it's used. New prompts go on top; favorites keep their own order.
    var results: [Prompt] {
        let live = PromptSearch.results(for: query, in: store.prompts, app: app)
        guard PromptSearch.terms(in: query).isEmpty else { return live }
        let rank = { (index: Int, prompt: Prompt) in (self.settledOrder[prompt.id] ?? -1, index) }
        let favorites = live.filter(\.isFavorite)
        let rest = live.filter { !$0.isFavorite }.enumerated()
            .sorted { rank($0.offset, $0.element) < rank($1.offset, $1.element) }
            .map(\.element)
        return favorites + rest
    }

    /// Lets usage since the last call reorder the list (call while the pointer is away).
    func settleOrder() {
        let live = PromptSearch.results(for: "", in: store.prompts, app: app)
        settledOrder = Dictionary(uniqueKeysWithValues: live.enumerated().map { ($1.id, $0) })
    }

    var selected: Prompt? {
        let results = results
        return results.first { $0.id == selectedID } ?? results.first
    }

    var favorites: [Prompt] { results.filter(\.isFavorite) }

    /// Called right before the shelf appears over `app`. An in-progress draft
    /// survives so closing the shelf mid-edit never loses work.
    func prepareForPresentation(app: String?) {
        self.app = app
        settleOrder()
        if draft == nil {
            query = ""
            selectedID = results.first?.id
        }
        filling = nil
        renamingID = nil
        isDiscardArmed = false
        errorMessage = nil
        presentationID += 1
    }

    func focusSearch() {
        searchFocusRequest += 1
    }

    func select(_ prompt: Prompt) {
        selectedID = prompt.id
    }

    func toggleFavorite(_ prompt: Prompt) {
        perform { try store.setFavorite(id: prompt.id, !prompt.isFavorite) }
    }

    /// Runs a store operation, surfacing failures in the shelf.
    func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Keyboard

    /// Returns whether the command was consumed.
    @discardableResult
    func handle(_ command: Command) -> Bool {
        errorMessage = nil
        if draft != nil { return handleWhileEditing(command) }
        if filling != nil { return handleWhileFilling(command) }
        if renamingID != nil { return handleWhileRenaming(command) }

        switch command {
        case .moveUp: moveSelection(by: -1)
        case .moveDown: moveSelection(by: 1)
        case .primary:
            if stackedIDs.isEmpty { selected.map { use([$0]) } } else { insertStack() }
        case .secondary: selected.map(copy)
        case .cancel:
            if !query.isEmpty { query = "" }
            else if !stackedIDs.isEmpty { stackedIDs = [] }
            else { actions.dismiss() }
        case .newPrompt: beginEditing(nil)
        case .edit: selected.map(beginEditing)
        case .delete: selected.map(delete)
        case .undo:
            // Nothing to undo here: let the search field undo its typing.
            guard recentlyDeleted != nil else { return false }
            undoDeletion()
        case .favorite: selected.map(toggleFavorite)
        case .close: actions.close()
        }
        return true
    }

    private func moveSelection(by offset: Int) {
        let results = results
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = results[min(max(current + offset, 0), results.count - 1)].id
    }
}

extension ShelfModel.Actions {
    /// Does nothing; replaced once the shelf's owner exists.
    static var none: Self {
        Self(
            insertText: { _, _ in }, copyText: { _, _ in }, readClipboard: { nil }, save: { _ in },
            promptCreated: { _ in }, setPinned: { _ in }, takeFocus: {}, releaseFocus: {},
            dismiss: {}, close: {}, preview: { _, _ in }
        )
    }
}
