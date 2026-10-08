import AppKit

/// Reveals the shelf from the left edge of any screen, like the auto-hiding Dock.
///
/// A 1-point invisible strip sits on each screen's left edge. Resting the pointer
/// there shows a glowing hint, then fires after the dwell time; clicking the hint
/// or dragging text onto the strip fires immediately.
@MainActor
final class ScreenEdgeTrigger {
    var isEnabled: Bool {
        didSet { rebuildStrips() }
    }
    var sensitivity: EdgeSensitivity
    var onTrigger: (NSScreen) -> Void = { _ in }
    /// When false (e.g. the shelf is already open) touching the edge does nothing.
    var isArmed: () -> Bool = { true }

    private var strips: [EdgeStripWindow] = []
    private let hint = EdgeHintWindow()
    private var dwellTask: Task<Void, Never>?

    init(isEnabled: Bool, sensitivity: EdgeSensitivity) {
        self.isEnabled = isEnabled
        self.sensitivity = sensitivity
        hint.onClick = { [weak self] in self?.fire() }
        hint.onPointerExited = { [weak self] in self?.pointerExited() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildStrips() }
        }
        rebuildStrips()
    }

    private var hoveredScreen: NSScreen?

    private func rebuildStrips() {
        strips.forEach { $0.orderOut(nil) }
        strips = []
        guard isEnabled else { return }
        strips = NSScreen.screens.map { screen in
            let strip = EdgeStripWindow(screen: screen)
            strip.onPointerEntered = { [weak self] y in self?.pointerEntered(screen, y: y) }
            strip.onPointerMoved = { [weak self] y in self?.hint.move(toY: y) }
            strip.onPointerExited = { [weak self] in self?.pointerExited() }
            strip.onDragEntered = { [weak self] in
                guard let self, isArmed() else { return }
                hoveredScreen = screen
                fire()
            }
            strip.orderFrontRegardless()
            return strip
        }
    }

    private func pointerEntered(_ screen: NSScreen, y: CGFloat) {
        guard isArmed() else { return }
        hoveredScreen = screen
        hint.show(on: screen, y: y)
        dwellTask?.cancel()
        dwellTask = Task { [weak self, sensitivity] in
            try? await Task.sleep(for: sensitivity.dwell)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    private func pointerExited() {
        // Moving from the strip onto the hint (or back) keeps it up: click it to open.
        let location = NSEvent.mouseLocation
        let isOnHint = hint.frame.insetBy(dx: -2, dy: -2).contains(location)
        let isOnStrip = strips.contains { $0.frame.insetBy(dx: -1, dy: 0).contains(location) }
        if !isOnStrip { dwellTask?.cancel() }
        if !isOnHint && !isOnStrip { hint.hide() }
    }

    private func fire() {
        dwellTask?.cancel()
        hint.hide()
        if let screen = hoveredScreen { onTrigger(screen) }
    }
}

/// An invisible, 1-point-wide window along a screen's left edge.
private final class EdgeStripWindow: NSPanel {
    var onPointerEntered: (CGFloat) -> Void = { _ in }
    var onPointerMoved: (CGFloat) -> Void = { _ in }
    var onPointerExited: () -> Void = {}
    var onDragEntered: () -> Void = {}

    init(screen: NSScreen) {
        let visible = screen.visibleFrame
        let frame = CGRect(x: screen.frame.minX, y: visible.minY, width: 1, height: visible.height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = NSColor.black.withAlphaComponent(0.001) // Fully clear windows don't receive events.
        isOpaque = false
        hasShadow = false
        let view = EdgeStripView(frame: CGRect(origin: .zero, size: frame.size))
        view.onPointerEntered = { [weak self] in self?.onPointerEntered($0) }
        view.onPointerMoved = { [weak self] in self?.onPointerMoved($0) }
        view.onPointerExited = { [weak self] in self?.onPointerExited() }
        view.onDragEntered = { [weak self] in self?.onDragEntered() }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
}

private final class EdgeStripView: NSView {
    var onPointerEntered: (CGFloat) -> Void = { _ in }
    var onPointerMoved: (CGFloat) -> Void = { _ in }
    var onPointerExited: () -> Void = {}
    var onDragEntered: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.string, .URL, .fileURL])
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    required init?(coder: NSCoder) { fatalError("Not used from nibs") }

    override func mouseEntered(with event: NSEvent) { onPointerEntered(NSEvent.mouseLocation.y) }
    override func mouseMoved(with event: NSEvent) { onPointerMoved(NSEvent.mouseLocation.y) }
    override func mouseExited(with event: NSEvent) { onPointerExited() }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDragEntered()
        return []
    }
}

/// The glowing pill that appears where the pointer touches the edge.
private final class EdgeHintWindow: NSPanel {
    var onClick: () -> Void = {}
    var onPointerExited: () -> Void = {}
    private static let size = CGSize(width: 7, height: 120)

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        let pill = HintPillView(frame: CGRect(origin: .zero, size: Self.size))
        pill.onClick = { [weak self] in self?.onClick() }
        pill.onPointerExited = { [weak self] in self?.onPointerExited() }
        contentView = pill
    }

    override var canBecomeKey: Bool { false }

    private var screenFrame: CGRect = .zero

    func show(on screen: NSScreen, y: CGFloat) {
        screenFrame = screen.visibleFrame
        setFrameOrigin(CGPoint(x: screen.frame.minX + 2, y: clampedY(y)))
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; animator().alphaValue = 1 }
    }

    func move(toY y: CGFloat) {
        guard isVisible else { return }
        setFrameOrigin(CGPoint(x: frame.minX, y: clampedY(y)))
    }

    func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; animator().alphaValue = 0 } completionHandler: {
            MainActor.assumeIsolated { if self.alphaValue == 0 { self.orderOut(nil) } }
        }
    }

    private func clampedY(_ y: CGFloat) -> CGFloat {
        min(max(y - Self.size.height / 2, screenFrame.minY + 8), screenFrame.maxY - Self.size.height - 8)
    }
}

private final class HintPillView: NSView {
    var onClick: () -> Void = {}
    var onPointerExited: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    required init?(coder: NSCoder) { fatalError("Not used from nibs") }

    override func mouseExited(with event: NSEvent) { onPointerExited() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
        NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
        path.fill()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Clicking or pulling the hint opens the shelf.
    override func mouseDown(with event: NSEvent) { onClick() }
}
