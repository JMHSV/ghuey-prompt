import AppKit

/// Backs the "Save to Ghuey Prompt" item in every app's right-click → Services menu.
/// The selector name must match `NSMessage` in Info.plist.
@MainActor
final class SaveTextService: NSObject {
    private let onText: (String) -> Void

    init(onText: @escaping (String) -> Void) {
        self.onText = onText
    }

    @objc func savePrompt(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pasteboard.string(forType: .string) else {
            error.pointee = "The selection doesn't contain text." as NSString
            return
        }
        onText(text)
    }
}
