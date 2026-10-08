import AppKit
import SwiftUI

/// A brief, non-interactive confirmation bubble near the bottom of the screen.
@MainActor
final class ToastPresenter {
    struct Toast {
        enum Style { case success, info, failure }
        let style: Style
        let title: String
        var detail: String?
    }

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ toast: Toast) {
        dismissTask?.cancel()
        panel?.orderOut(nil)

        let hosting = NSHostingView(rootView: ToastView(toast: toast))
        let size = hosting.fittingSize
        let panel = FloatingPanel(size: size, cornerRadius: size.height / 2, content: hosting)
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.hasShadow = true

        if let visible = NSScreen.underMouse?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 96))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        self.panel = panel

        dismissTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(toast.detail == nil ? 1.4 : 2.2))
            guard !Task.isCancelled, let panel else { return }
            await NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 0 }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            if self?.panel === panel { self?.panel = nil }
        }
    }
}

private struct ToastView: View {
    let toast: ToastPresenter.Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(icon.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail = toast.detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .padding(.vertical, toast.detail == nil ? 11 : 9)
        .fixedSize()
    }

    private var icon: (name: String, color: Color) {
        switch toast.style {
        case .success: ("checkmark.circle.fill", .green)
        case .info: ("info.circle.fill", .secondary)
        case .failure: ("exclamationmark.triangle.fill", .orange)
        }
    }
}
