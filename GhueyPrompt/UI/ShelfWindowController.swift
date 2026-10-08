import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Presents the shelf along the left edge of a screen and routes its keyboard shortcuts.
///
/// The panel never activates the app, so the app you're working in stays frontmost.
/// It takes keyboard focus only while it's being used from the keyboard, and hands it
/// back before inserting so text lands where your cursor was.
@MainActor
final class ShelfWindowController {
    enum Presentation {
        case hidden
        /// Shown briefly after saving from elsewhere; never takes focus.
        case announcing
        /// Revealed from the screen edge; hides once the pointer moves away.
        case peeking
        /// Opened with the hotkey; closes on Esc, a click elsewhere, or after inserting.
        case transient
        /// Stays until unpinned or toggled closed.
        case pinned

        /// Whether opening this way should put the cursor in the search field.
        var takesFocus: Bool { self == .peeking || self == .transient }
    }

    static let width: CGFloat = 320
    static let margin: CGFloat = 10
    private static let slideDistance: CGFloat = 28
    private static let announceDuration: TimeInterval = 2.2

    let model: ShelfModel
    private let panel: FloatingPanel
    private let preview = PromptPreviewPanel()
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?
    private var pointerTimer: Timer?
    private var pointerLeftAt: Date?
    private var isPointerInside = false
    private var announceDeadline: Date?
    private var screen: NSScreen?

    /// Called whenever the shelf opens, however it was summoned.
    var onShow: () -> Void = {}

    private(set) var presentation: Presentation = .hidden {
        didSet {
            model.isPinned = presentation == .pinned
            updateOutsideClickMonitor()
            updatePointerTimer()
        }
    }

    var isVisible: Bool { presentation != .hidden }

    init(model: ShelfModel) {
        self.model = model
        let hosting = FirstMouseHostingView(rootView: ShelfView(model: model))
        hosting.sizingOptions = []
        panel = FloatingPanel(size: CGSize(width: Self.width, height: 600), cornerRadius: 24, content: hosting)
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === panel else { return event }
            return handle(event) ? nil : event
        }
    }

    func toggle() {
        presentation == .hidden || presentation == .announcing ? show(.transient) : hide()
    }

    /// Shows the shelf on `screen` (default: where it is, else under the pointer).
    /// A stronger presentation is never downgraded by a weaker request.
    func show(_ requested: Presentation, on screen: NSScreen? = nil) {
        let target = screen ?? self.screen ?? NSScreen.underMouse
        if presentation == .hidden || target != self.screen {
            model.prepareForPresentation(app: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            slideIn(on: target)
            onShow()
        }
        if Self.strength(requested) >= Self.strength(presentation) {
            presentation = requested
        }
        announceDeadline = requested == .announcing ? .now + Self.announceDuration : nil
        if requested.takesFocus {
            takeFocus()
            model.focusSearch()
        }
    }

    func setPinned(_ pinned: Bool) {
        guard isVisible else { return }
        presentation = pinned ? .pinned : .transient
    }

    func hide() {
        guard isVisible else { return }
        // Give focus back right away: an insert may be about to type into that app.
        releaseFocus()
        presentation = .hidden
        preview.hide()
        slideOut()
    }

    /// Esc with nothing left to clear.
    func dismiss() {
        presentation == .pinned ? releaseFocus() : hide()
    }

    /// After inserting: a hotkey shelf has done its job; others stay for more.
    func didInsert() {
        presentation == .transient ? hide() : releaseFocus()
    }

    func takeFocus() {
        panel.makeKey()
    }

    /// Returns keyboard focus to the app you were typing in. The panel isn't part of
    /// that app, so re-ordering it is the way to give up key status without hiding.
    func releaseFocus() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        if isVisible { panel.orderFrontRegardless() }
    }

    /// `card` is in the shelf's SwiftUI global space (top-left origin).
    func previewHover(_ prompt: Prompt?, card: CGRect) {
        let isBusy = model.draft != nil || model.filling != nil || model.draggedPromptID != nil
            || NSEvent.pressedMouseButtons != 0
        guard let prompt, !isBusy else {
            preview.hover(nil, card: .zero, shelf: .zero)
            return
        }
        let onScreen = CGRect(
            x: panel.frame.minX + card.minX, y: panel.frame.maxY - card.maxY,
            width: card.width, height: card.height
        )
        preview.hover(prompt, card: onScreen, shelf: panel.frame)
    }

    func hidePreview() {
        preview.hide()
    }

    private static func strength(_ presentation: Presentation) -> Int {
        switch presentation {
        case .hidden: 0
        case .announcing: 1
        case .peeking: 2
        case .transient: 3
        case .pinned: 4
        }
    }

    // MARK: Animation

    private func slideIn(on screen: NSScreen?) {
        guard let screen else { return }
        self.screen = screen
        let visible = screen.visibleFrame
        let frame = CGRect(
            x: visible.minX + Self.margin,
            y: visible.minY + Self.margin,
            width: Self.width,
            height: visible.height - 2 * Self.margin
        )
        panel.setFrame(frame.offsetBy(dx: -Self.slideDistance, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            // Overshoot slightly, like a spring settling into place.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.2, 0.35, 1)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func slideOut() {
        screen = nil
        let target = panel.frame.offsetBy(dx: -Self.slideDistance, dy: 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.presentation == .hidden else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    // MARK: Closing on their own

    /// A hotkey shelf closes when you click anywhere else or switch apps.
    private func updateOutsideClickMonitor() {
        guard presentation == .transient else {
            outsideClickMonitor.map(NSEvent.removeMonitor)
            outsideClickMonitor = nil
            appSwitchObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
            appSwitchObserver = nil
            return
        }
        guard outsideClickMonitor == nil else { return }
        // Global monitors only see events bound for other apps — exactly "outside".
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideUnlessMidTask() }
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideUnlessMidTask() }
        }
    }

    /// Half-written prompts and half-filled blanks keep the shelf open.
    private func hideUnlessMidTask() {
        guard model.draft == nil, model.filling == nil else { return }
        hide()
    }

    private func updatePointerTimer() {
        guard isVisible else {
            pointerTimer?.invalidate()
            pointerTimer = nil
            return
        }
        pointerLeftAt = nil
        guard pointerTimer == nil else { return }
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
    }

    /// Follows the pointer to auto-hide a peeking or announcing shelf, and to let the
    /// list re-sort only while you're not looking at it.
    private func trackPointer() {
        let isInside = panel.frame.insetBy(dx: -24, dy: -24).contains(NSEvent.mouseLocation)
        if isInside != isPointerInside {
            isPointerInside = isInside
            if !isInside {
                preview.hide()
                model.settleOrder()
            }
        }

        // Typing a search turns a peek into something you dismiss deliberately.
        if presentation == .peeking, !model.query.isEmpty {
            presentation = .transient
            return
        }

        switch presentation {
        case .announcing:
            if isInside {
                presentation = .peeking
            } else if let announceDeadline, announceDeadline < .now {
                hide()
            }
        case .peeking:
            let isBusy = NSEvent.pressedMouseButtons != 0 || model.draft != nil
                || model.filling != nil || model.renamingID != nil
            guard !isBusy, !isInside else {
                pointerLeftAt = nil
                return
            }
            if let pointerLeftAt, Date.now.timeIntervalSince(pointerLeftAt) > 0.3 {
                hide()
            } else if pointerLeftAt == nil {
                pointerLeftAt = .now
            }
        case .hidden, .transient, .pinned:
            break
        }
    }

    // MARK: Keyboard

    private func handle(_ event: NSEvent) -> Bool {
        // Let input methods (e.g. Japanese) finish composing before we act on ↩ or esc.
        if let textView = panel.firstResponder as? NSTextView, textView.hasMarkedText() { return false }
        guard let command = Self.command(for: event) else { return false }
        return model.handle(command)
    }

    private static func command(for event: NSEvent) -> ShelfModel.Command? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        switch (modifiers, Int(event.keyCode)) {
        case ([], kVK_UpArrow), (.control, kVK_ANSI_P): return .moveUp
        case ([], kVK_DownArrow), (.control, kVK_ANSI_N): return .moveDown
        case ([], kVK_Return), ([], kVK_ANSI_KeypadEnter): return .primary
        case (.command, kVK_Return), (.command, kVK_ANSI_KeypadEnter), (.command, kVK_ANSI_S): return .secondary
        case ([], kVK_Escape): return .cancel
        case (.command, kVK_ANSI_N): return .newPrompt
        case (.command, kVK_ANSI_E): return .edit
        case (.command, kVK_Delete): return .delete
        case (.command, kVK_ANSI_Z): return .undo
        case (.command, kVK_ANSI_D): return .favorite
        case (.command, kVK_ANSI_W): return .close
        default: return nil
        }
    }
}
