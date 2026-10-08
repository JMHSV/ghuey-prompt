import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut, registered through Carbon (no permissions needed).
/// Stays registered until `unregister()` is called.
@MainActor
final class GlobalHotKey {
    struct Shortcut {
        let keyCode: Int
        let modifiers: NSEvent.ModifierFlags
        /// Human-readable form, e.g. "⌥⌘P".
        let display: String
    }

    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?

    init(_ shortcut: Shortcut, action: @escaping () -> Void) throws {
        Self.installEventHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x504C_4942) /* "PLIB" */, id: id)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.modifiers),
            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr else { throw HotKeyError.registrationFailed(shortcut.display, status) }
        Self.handlers[id] = action
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
        Self.handlers[id] = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            MainActor.assumeIsolated { GlobalHotKey.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }
}

enum HotKeyError: LocalizedError {
    case registrationFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case let .registrationFailed(display, status):
            "Couldn't register the \(display) shortcut (error \(status)). Another app may already use it."
        }
    }
}
