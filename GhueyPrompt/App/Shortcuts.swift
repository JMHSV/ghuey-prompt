import AppKit
import Carbon.HIToolbox

enum Shortcuts {
    static let toggleShelf = GlobalHotKey.Shortcut(keyCode: kVK_ANSI_P, modifiers: [.option, .command], display: "⌥⌘P")
    static let saveSelection = GlobalHotKey.Shortcut(keyCode: kVK_ANSI_P, modifiers: [.shift, .option, .command], display: "⇧⌥⌘P")
}
