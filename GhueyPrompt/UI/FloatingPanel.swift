import AppKit
import SwiftUI

/// A borderless panel that can take keyboard focus without activating the app,
/// so the app you were typing in stays frontmost (like Spotlight or Raycast).
final class FloatingPanel: NSPanel {
    init(size: CGSize, cornerRadius: CGFloat, content: NSView) {
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // We animate showing and hiding ourselves. The system fade would also play when
        // the shelf hands focus back (orderOut + orderFront), making it blink on every click.
        animationBehavior = .none
        contentView = Self.materialView(cornerRadius: cornerRadius, wrapping: content)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Liquid Glass where available, vibrant blur before that.
    private static func materialView(cornerRadius: CGFloat, wrapping content: NSView) -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            // A light tint keeps text legible over busy windows.
            glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.35)
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }
}

/// Hosts SwiftUI in a panel of an app that is never active, where AppKit would
/// otherwise swallow the first click as "activate the window".
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSScreen {
    /// The screen the user is looking at: the one under the mouse pointer.
    static var underMouse: NSScreen? {
        screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? main
    }
}
