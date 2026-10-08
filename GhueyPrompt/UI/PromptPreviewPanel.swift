import AppKit
import SwiftUI

/// Shows a prompt's full text in a glass panel beside the shelf when the pointer
/// rests on a card. Once one preview is up, moving to another card swaps instantly.
@MainActor
final class PromptPreviewPanel {
    static let width: CGFloat = 380
    private static let holdDelay: Duration = .milliseconds(550)
    private static let gap: CGFloat = 8

    private let hosting = NSHostingView(rootView: PreviewView(prompt: nil))
    private let panel: FloatingPanel
    private var pending: Task<Void, Never>?
    private var shownID: Prompt.ID?

    init() {
        hosting.sizingOptions = []
        panel = FloatingPanel(size: CGSize(width: Self.width, height: 200), cornerRadius: 20, content: hosting)
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
    }

    /// `card` and `shelf` are in screen coordinates.
    func hover(_ prompt: Prompt?, card: CGRect, shelf: CGRect) {
        pending?.cancel()
        guard let prompt else {
            // A short grace so gliding between cards doesn't flicker.
            pending = Task {
                try? await Task.sleep(for: .milliseconds(120))
                if !Task.isCancelled { hide() }
            }
            return
        }
        if shownID != nil {
            show(prompt, card: card, shelf: shelf)
            return
        }
        pending = Task {
            try? await Task.sleep(for: Self.holdDelay)
            if !Task.isCancelled { show(prompt, card: card, shelf: shelf) }
        }
    }

    func hide() {
        pending?.cancel()
        guard shownID != nil else { return }
        shownID = nil
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 0 } completionHandler: {
            MainActor.assumeIsolated { if self.shownID == nil { self.panel.orderOut(nil) } }
        }
    }

    /// The height the preview needs at its fixed width. (The panel's hosting view has
    /// sizing disabled so it can't resize the window itself, which also makes its
    /// `fittingSize` zero, so measure separately.)
    static func contentHeight(for prompt: Prompt) -> CGFloat {
        NSHostingController(rootView: PreviewView(prompt: prompt))
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    private func show(_ prompt: Prompt, card: CGRect, shelf: CGRect) {
        guard prompt.id != shownID, let screen = NSScreen.screens.first(where: { $0.frame.intersects(shelf) }) else { return }
        let isAppearing = shownID == nil
        shownID = prompt.id
        hosting.rootView = PreviewView(prompt: prompt)

        let visible = screen.visibleFrame
        let height = min(Self.contentHeight(for: prompt), visible.height * 0.7)
        let y = min(max(card.midY - height / 2, visible.minY + 10), visible.maxY - height - 10)
        let frame = CGRect(x: shelf.maxX + Self.gap, y: y, width: Self.width, height: height)

        if isAppearing {
            panel.setFrame(frame.offsetBy(dx: -10, dy: 0), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isAppearing ? 0.2 : 0.14
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }
}

private struct PreviewView: View {
    let prompt: Prompt?

    var body: some View {
        if let prompt {
            VStack(alignment: .leading, spacing: 10) {
                Text(prompt.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(Self.highlightingPlaceholders(prompt.body))
                    .font(.system(size: 12.5))
                    .lineSpacing(2.5)
                    .lineLimit(40)
                    .foregroundStyle(.primary.opacity(0.85))
                if prompt.useCount > 0 {
                    Text("Used \(prompt.useCount) time\(prompt.useCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(18)
            .frame(width: PromptPreviewPanel.width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Placeholders stand out so it's clear what will be asked for.
    private static func highlightingPlaceholders(_ body: String) -> AttributedString {
        var text = AttributedString(body)
        for match in body.matches(of: /\{\{[^{}]+\}\}/) {
            guard let range = Range(match.range, in: text) else { continue }
            text[range].foregroundColor = .accentColor
            text[range].font = .system(size: 12.5, weight: .semibold)
        }
        return text
    }
}
