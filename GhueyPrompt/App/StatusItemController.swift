import AppKit
import ServiceManagement

/// The menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let coordinator: AppCoordinator
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let revealOnEdgeItem = NSMenuItem(title: "Reveal at Left Screen Edge", action: #selector(toggleRevealOnEdge), keyEquivalent: "")
    private let iCloudItem = NSMenuItem(title: "Sync with iCloud Drive", action: #selector(toggleICloud), keyEquivalent: "")
    private let sensitivityItems = EdgeSensitivity.allCases.map { sensitivity in
        let item = NSMenuItem(title: sensitivity.title, action: #selector(setSensitivity), keyEquivalent: "")
        item.representedObject = sensitivity.rawValue
        return item
    }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
        let icon = NSImage(resource: .statusIcon)
        icon.accessibilityDescription = "Ghuey Prompt"
        statusItem.button?.image = icon

        // Enabled states are set in menuNeedsUpdate.
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(item("Show Shelf", Shortcuts.toggleShelf, #selector(toggleShelf)))
        menu.addItem(item("Save Selected Text", Shortcuts.saveSelection, #selector(saveSelection)))
        menu.addItem(.separator())

        revealOnEdgeItem.target = self
        menu.addItem(revealOnEdgeItem)
        let sensitivityMenu = NSMenu()
        sensitivityMenu.autoenablesItems = false
        for item in sensitivityItems {
            item.target = self
            sensitivityMenu.addItem(item)
        }
        let sensitivityItem = NSMenuItem(title: "Edge Sensitivity", action: nil, keyEquivalent: "")
        sensitivityItem.submenu = sensitivityMenu
        menu.addItem(sensitivityItem)

        iCloudItem.target = self
        menu.addItem(iCloudItem)
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())

        menu.addItem(item("Welcome Tour…", nil, #selector(showTour)))
        menu.addItem(item("Show Prompts File", nil, #selector(revealFile)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ghuey Prompt", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        revealOnEdgeItem.state = coordinator.revealsOnScreenEdge ? .on : .off
        for item in sensitivityItems {
            item.state = item.representedObject as? String == coordinator.edgeSensitivity.rawValue ? .on : .off
            item.isEnabled = coordinator.revealsOnScreenEdge
        }
        let isInICloud = AppSettings.libraryLocation == .iCloudDrive
        iCloudItem.state = isInICloud ? .on : .off
        iCloudItem.isEnabled = isInICloud || LibraryLocation.isICloudDriveAvailable
        iCloudItem.toolTip = iCloudItem.isEnabled ? nil : "Turn on iCloud Drive in System Settings to sync."
    }

    private func item(_ title: String, _ shortcut: GlobalHotKey.Shortcut?, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let shortcut {
            // Display-only: the global hotkey does the real work.
            item.keyEquivalent = shortcut.display.last.map { String($0).lowercased() } ?? ""
            item.keyEquivalentModifierMask = shortcut.modifiers
        }
        return item
    }

    @objc private func toggleShelf() { coordinator.shelf.toggle() }

    @objc private func saveSelection() { coordinator.saveSelection() }

    @objc private func toggleRevealOnEdge() { coordinator.revealsOnScreenEdge.toggle() }

    @objc private func setSensitivity(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let sensitivity = EdgeSensitivity(rawValue: raw) else { return }
        coordinator.edgeSensitivity = sensitivity
    }

    @objc private func toggleICloud() {
        let destination: LibraryLocation = AppSettings.libraryLocation == .iCloudDrive ? .thisMac : .iCloudDrive
        do {
            try coordinator.moveLibrary(to: destination)
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }

    @objc private func showTour() { coordinator.onboarding.show() }

    @objc private func revealFile() {
        NSWorkspace.shared.activateFileViewerSelecting([coordinator.store.fileURL])
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }
}
