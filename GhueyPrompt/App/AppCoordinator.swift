import AppKit
import OSLog

/// Carries out the app's user-facing actions — inserting, copying and saving prompts —
/// and connects the shelf to the screen edge, hotkeys, settings and the library file.
@MainActor
final class AppCoordinator {
    let store: PromptStore
    let shelf: ShelfWindowController
    let onboarding: OnboardingWindow
    private let edgeTrigger: ScreenEdgeTrigger
    private let toasts = ToastPresenter()
    private var favoriteHotKeys: FavoriteHotKeys?
    private var watcher: FileWatcher?
    private static let log = Logger(subsystem: "com.homesetv.GhueyPrompt", category: "app")

    init(store: PromptStore) {
        self.store = store
        let model = ShelfModel(store: store)
        shelf = ShelfWindowController(model: model)
        onboarding = OnboardingWindow { [store] in store.prompts.count }
        edgeTrigger = ScreenEdgeTrigger(isEnabled: AppSettings.revealsOnScreenEdge, sensitivity: AppSettings.edgeSensitivity)

        model.actions = .init(
            insertText: { [unowned self] in insert($0, ids: $1) },
            copyText: { [unowned self] in copy($0, ids: $1) },
            readClipboard: { NSPasteboard.general.string(forType: .string) },
            save: { [unowned self] in save($0) },
            promptCreated: { [unowned self] in improveTitle(of: $0) },
            setPinned: { [unowned self] in shelf.setPinned($0) },
            takeFocus: { [unowned self] in shelf.takeFocus() },
            releaseFocus: { [unowned self] in shelf.releaseFocus() },
            dismiss: { [unowned self] in shelf.dismiss() },
            close: { [unowned self] in shelf.hide() },
            preview: { [unowned self] in shelf.previewHover($0, card: $1) }
        )
        shelf.onShow = { [unowned self] in onboarding.shelfDidOpen() }
        edgeTrigger.onTrigger = { [unowned self] screen in shelf.show(.peeking, on: screen) }
        edgeTrigger.isArmed = { [unowned self] in !shelf.isVisible || shelf.presentation == .announcing }
        favoriteHotKeys = FavoriteHotKeys { [unowned self] in useFavorite(at: $0) }

        observeStore()
        watchLibrary()
    }

    // MARK: Settings

    var revealsOnScreenEdge: Bool {
        get { edgeTrigger.isEnabled }
        set {
            edgeTrigger.isEnabled = newValue
            AppSettings.revealsOnScreenEdge = newValue
        }
    }

    var edgeSensitivity: EdgeSensitivity {
        get { edgeTrigger.sensitivity }
        set {
            edgeTrigger.sensitivity = newValue
            AppSettings.edgeSensitivity = newValue
        }
    }

    /// Moves the library file, merging with any library already at the destination.
    /// The old file stays where it was, as a backup.
    func moveLibrary(to location: LibraryLocation) throws {
        try store.relocate(to: location.fileURL)
        AppSettings.libraryLocation = location
        watchLibrary()
    }

    // MARK: Using prompts

    /// Types `text` into whatever text field has the cursor.
    func insert(_ text: String, ids: [Prompt.ID]) {
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard Accessibility.isTrusted else {
            TextTransfer.copy(text)
            recordUse(ids, in: app)
            Accessibility.requestTrust()
            toasts.show(.init(style: .info, title: "Copied — press ⌘V to paste",
                              detail: "Allow Accessibility access to insert automatically"))
            return
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        shelf.didInsert()
        recordUse(ids, in: app)
        Task { await TextTransfer.paste(text) }
    }

    func copy(_ text: String, ids: [Prompt.ID]) {
        recordUse(ids, in: nil)
        TextTransfer.copy(text)
        toasts.show(.init(style: .success, title: "Copied to Clipboard"))
    }

    /// ⌃⌥N: inserts the Nth favorite right away, opening the shelf only if it has blanks to fill.
    func useFavorite(at index: Int) {
        let favorites = PromptSearch.results(for: "", in: store.prompts).filter(\.isFavorite)
        guard favorites.indices.contains(index) else { return }
        let prompt = favorites[index]
        if !PromptTemplate.fields(in: prompt.body).isEmpty {
            shelf.show(.transient)
        }
        shelf.model.use([prompt])
        if let error = shelf.model.errorMessage, !shelf.isVisible {
            toasts.show(.init(style: .failure, title: "Couldn't insert “\(prompt.title)”", detail: error))
        }
    }

    private func recordUse(_ ids: [Prompt.ID], in app: String?) {
        do {
            for id in ids { try store.recordUse(id: id, in: app) }
        } catch {
            toasts.show(.init(style: .failure, title: "Couldn't update prompt", detail: error.localizedDescription))
        }
    }

    // MARK: Saving prompts

    /// Grabs the selected text in the frontmost app and saves it.
    func saveSelection() {
        guard Accessibility.isTrusted else {
            Accessibility.requestTrust()
            toasts.show(.init(style: .info, title: "Allow Accessibility access",
                              detail: "Needed to read the text you've selected"))
            return
        }
        Task {
            guard let text = await TextTransfer.copySelection(),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                toasts.show(.init(style: .info, title: "No text selected"))
                return
            }
            save(text)
        }
    }

    /// Saves `text` and shows it arriving on the shelf, without taking focus.
    func save(_ text: String) {
        do {
            let outcome = try store.save(text: text)
            if !shelf.isVisible { shelf.show(.announcing) }
            switch outcome {
            case let .created(prompt):
                shelf.model.announceAdded(prompt.id)
                improveTitle(of: prompt)
            case let .alreadySaved(prompt):
                shelf.model.announceAdded(prompt.id)
                toasts.show(.init(style: .info, title: "Already in your library", detail: prompt.title))
            }
        } catch {
            toasts.show(.init(style: .failure, title: "Couldn't save prompt", detail: error.localizedDescription))
        }
    }

    /// Replaces a title derived from the first line with one written by the on-device model.
    private func improveTitle(of prompt: Prompt) {
        guard prompt.title == PromptTitle.derive(from: prompt.body), TitleGenerator.isAvailable else { return }
        Task {
            guard let title = await TitleGenerator.title(for: prompt.body) else { return }
            do {
                try store.applyGeneratedTitle(title, to: prompt.id, replacing: prompt.title)
            } catch {
                Self.log.error("Couldn't apply generated title: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Keeping up with the library

    private func observeStore() {
        favoriteHotKeys?.update(favoriteCount: store.prompts.count { $0.isFavorite })
        onboarding.promptCountChanged(to: store.prompts.count)
        withObservationTracking {
            _ = store.prompts
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }

    /// Picks up edits from elsewhere: another Mac through iCloud Drive, or a text editor.
    private func watchLibrary() {
        watcher?.stop()
        do {
            watcher = try FileWatcher(directory: store.fileURL.deletingLastPathComponent()) { [weak self] in
                self?.reloadLibrary()
            }
        } catch {
            toasts.show(.init(style: .failure, title: "Can't watch the library for changes", detail: error.localizedDescription))
        }
    }

    private func reloadLibrary() {
        do {
            try store.reloadFromDisk()
        } catch {
            toasts.show(.init(style: .failure, title: "Couldn't read changes to your library", detail: error.localizedDescription))
        }
    }
}
