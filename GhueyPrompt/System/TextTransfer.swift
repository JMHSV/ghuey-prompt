import AppKit
import Carbon.HIToolbox

/// Moves text between the pasteboard and the frontmost app by synthesizing ⌘C / ⌘V.
@MainActor
enum TextTransfer {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Pastes `text` into whichever app is frontmost, then puts back what the user
    /// had on the clipboard. Requires Accessibility trust; callers must check it first.
    static func paste(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        copy(text)
        let ourChange = pasteboard.changeCount

        await waitForModifierRelease()
        // Give the previously focused window a beat to regain key status.
        try? await Task.sleep(for: .milliseconds(60))
        postCommandKey(kVK_ANSI_V)

        // Apps read the pasteboard while handling ⌘V; restore once they're done,
        // unless something else has been copied in the meantime.
        try? await Task.sleep(for: .milliseconds(500))
        if pasteboard.changeCount == ourChange { restore(saved, to: pasteboard) }
    }

    /// Copies the frontmost app's current selection and returns it, leaving the
    /// user's clipboard as it was. Returns nil when nothing is selected.
    static func copySelection() async -> String? {
        await waitForModifierRelease()

        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let changeCount = pasteboard.changeCount

        postCommandKey(kVK_ANSI_C)

        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(25))
            if pasteboard.changeCount != changeCount {
                let copied = pasteboard.string(forType: .string)
                restore(saved, to: pasteboard)
                return copied
            }
        }
        return nil
    }

    private static func postCommandKey(_ keyCode: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// A hotkey fires while its modifiers are still held; synthesizing ⌘C or ⌘V then
    /// would arrive as e.g. ⇧⌥⌘C in some apps. Wait (briefly) for a clean keyboard.
    private static func waitForModifierRelease() async {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        for _ in 0..<40 {
            if CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: modifiers) { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]

    private static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
