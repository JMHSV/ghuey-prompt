import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var statusItem: StatusItemController?
    private var hotKeys: [GlobalHotKey] = []
    private var saveTextService: SaveTextService?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app; keep them free of hotkeys and windows.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let store: PromptStore
        do {
            // Before reading settings: the library location may come from the old app.
            try LegacyMigration.run()
            store = try PromptStore(fileURL: AppSettings.libraryLocation.fileURL)
        } catch {
            presentUnreadableLibrary(error)
            return
        }

        let coordinator = AppCoordinator(store: store)
        self.coordinator = coordinator
        statusItem = StatusItemController(coordinator: coordinator)

        let service = SaveTextService { [weak coordinator] in coordinator?.save($0) }
        saveTextService = service
        NSApp.servicesProvider = service
        NSUpdateDynamicServices()

        registerHotKeys(for: coordinator)

        if !AppSettings.hasCompletedOnboarding {
            coordinator.onboarding.show()
        }
    }

    /// Opening the app again (Finder, Spotlight, Dock) brings up the shelf.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        coordinator?.shelf.show(.pinned)
        return false
    }

    private func registerHotKeys(for coordinator: AppCoordinator) {
        let bindings: [(GlobalHotKey.Shortcut, () -> Void)] = [
            (Shortcuts.toggleShelf, { [weak coordinator] in coordinator?.shelf.toggle() }),
            (Shortcuts.saveSelection, { [weak coordinator] in coordinator?.saveSelection() }),
        ]
        for (shortcut, action) in bindings {
            do {
                hotKeys.append(try GlobalHotKey(shortcut, action: action))
            } catch {
                NSApp.activate()
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Never start with an empty library over a file we couldn't read: that would
    /// overwrite the user's prompts on the next save.
    private func presentUnreadableLibrary(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Ghuey Prompt couldn't read your prompts"
        let fileURL = AppSettings.libraryLocation.fileURL
        alert.informativeText = "\(fileURL.path)\n\n\(error.localizedDescription)\n\nFix or move the file, then reopen the app."
        alert.addButton(withTitle: "Show File")
        alert.addButton(withTitle: "Quit")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
        NSApp.terminate(nil)
    }
}
