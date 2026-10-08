import AppKit
import Carbon.HIToolbox
import OSLog

/// ⌃⌥1 … ⌃⌥9 insert the first nine favorites from anywhere. Only as many shortcuts
/// are registered as there are favorites, so unused combinations stay free for other apps.
/// (⌃1–9 alone would collide with Mission Control's "Switch to Desktop N".)
@MainActor
final class FavoriteHotKeys {
    static let modifiers: NSEvent.ModifierFlags = [.control, .option]
    private static let keyCodes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]
    private static let log = Logger(subsystem: "com.homesetv.GhueyPrompt", category: "hotkeys")

    private var registered: [GlobalHotKey] = []
    private let onPress: (Int) -> Void

    /// `onPress` receives the zero-based favorite index.
    init(onPress: @escaping (Int) -> Void) {
        self.onPress = onPress
    }

    func update(favoriteCount: Int) {
        let wanted = min(favoriteCount, Self.keyCodes.count)
        while registered.count > wanted {
            registered.removeLast().unregister()
        }
        while registered.count < wanted {
            let index = registered.count
            let shortcut = GlobalHotKey.Shortcut(
                keyCode: Self.keyCodes[index], modifiers: Self.modifiers, display: "⌃⌥\(index + 1)"
            )
            do {
                registered.append(try GlobalHotKey(shortcut) { [onPress] in onPress(index) })
            } catch {
                // Another app owns this combination; the rest still work.
                Self.log.error("\(error.localizedDescription, privacy: .public)")
                return
            }
        }
    }
}
