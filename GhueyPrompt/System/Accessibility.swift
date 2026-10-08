import ApplicationServices

/// Pasting into and copying from other apps means synthesizing keystrokes,
/// which macOS gates behind the Accessibility permission.
enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that deep-links to Privacy & Security → Accessibility.
    static func requestTrust() {
        // The literal value of kAXTrustedCheckOptionPrompt, which Swift 6 flags as unsafe global state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
