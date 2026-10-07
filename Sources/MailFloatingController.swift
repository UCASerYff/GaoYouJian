import AppKit
import Combine
import SwiftUI

/// A drag ends on a native mouse-up event, never on return from an asynchronous AppKit request.
struct MailFloatingDragSession {
    private(set) var isPressed = false
    private(set) var didDrag = false
    private var pressedAt = NSPoint.zero
    private var grabOffset = NSSize.zero
    static let threshold: CGFloat = 4

    mutating func begin(pointer: NSPoint, frame: NSRect) {
        isPressed = true
        didDrag = false
        pressedAt = pointer
        grabOffset = NSSize(width: pointer.x - frame.minX, height: pointer.y - frame.minY)
    }

    mutating func carry(pointer: NSPoint) -> NSSize? {
        guard isPressed else { return nil }
        if !didDrag && hypot(pointer.x - pressedAt.x, pointer.y - pressedAt.y) >= Self.threshold { didDrag = true }
        return didDrag ? grabOffset : nil
    }

    mutating func finish() -> Bool? {
        guard isPressed else { return nil }
        let moved = didDrag
        isPressed = false
        didDrag = false
        return moved
    }
}

/// A nonactivating utility panel: showing mail counts never takes focus from the user's current app.
@MainActor
private final class MailFloatingPanel: NSPanel {
    var dismiss: (() -> Void)?
    var allowsKey = true
    let dragHandles = NSHashTable<NSView>.weakObjects()
    var onPressChanged: ((Bool) -> Void)?
    var onDrag: ((NSPoint, NSSize) -> Void)?
    var onRelease: ((Bool) -> Void)?
    private var dragSession = MailFloatingDragSession()
    var isPressed: Bool { dragSession.isPressed }
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss?() }
        else { super.keyDown(with: event) }
    }

    /// Window-level interception precedes NSHostingView hit testing and works from another foreground app.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if isGrabEvent(event) {
                dragSession.begin(pointer: convertPoint(toScreen: event.locationInWindow), frame: frame)
                onPressChanged?(true)
                return
            }
        case .leftMouseDragged where isPressed:
            let pointer = convertPoint(toScreen: event.locationInWindow)
            if let offset = dragSession.carry(pointer: pointer) { onDrag?(pointer, offset) }
            return
        case .leftMouseUp where isPressed:
            if let dragged = dragSession.finish() {
                onPressChanged?(false)
                onRelease?(dragged)
            }
            return
        default: break
        }
        super.sendEvent(event)
    }

    func cancelInteraction() {
        if dragSession.finish() != nil { onPressChanged?(false) }
    }

    func isGrabEvent(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown, !event.modifierFlags.contains(.control) else { return false }
        if !allowsKey { return frame.contains(convertPoint(toScreen: event.locationInWindow)) }
        return dragHandles.allObjects.contains { view in
            view.window === self && !view.isHidden && view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
    }
}

@MainActor
final class MailFloatingController: NSObject, ObservableObject, NSWindowDelegate, NSMenuDelegate {
    @Published private(set) var isVisible = false
    @Published private(set) var isExpanded = false
    @Published private(set) var isOnLeft = false
    @Published var isPinned: Bool {
        didSet {
            defaults.set(isPinned, forKey: Key.pinned)
            if isPinned && isVisible { expand() }
            lastInsideAt = Date()
        }
    }
    @Published var isCompact: Bool {
        didSet {
            guard oldValue != isCompact else { return }
            defaults.set(isCompact, forKey: Key.compact)
            if let panel { applyRestoredFrame(to: panel) }
        }
    }
    @Published var showPreviews: Bool {
        didSet { defaults.set(showPreviews, forKey: Key.previews) }
    }
    @Published var opacity: Double {
        didSet {
            let safe = Self.safeOpacity(opacity)
            if opacity != safe { opacity = safe }
            defaults.set(safe, forKey: Key.opacity)
            panel?.alphaValue = safe
        }
    }

    var onOpenInbox: ((UUID?, String?) -> Void)?
    var onCompose: ((UUID?) -> Void)?
    var onOpenSettings: (() -> Void)?

    private let store: MailStore
    private let defaults: UserDefaults
    private var panel: MailFloatingPanel?
    private var statusItem: NSStatusItem?
    private var visibilityMenuItem: NSMenuItem?
    private var didRestoreVisibility = false
    private var isApplyingFrame = false
    private var savedVisible: Bool
    private var rememberedDisplay: String?
    private var verticalRatio: Double
    private var pointerTimer: Timer?
    private var lastInsideAt = Date()
    private var trackingMenus = Set<ObjectIdentifier>()
    private var externalMenuOpen = false
    private var revealRequiresExit = false
    private var hoverStartedAt: Date?
    #if DEBUG_TESTING
    private var suppressPanelPresentationForTesting = false
    #endif
    private static let margin: CGFloat = 12
    static let expandedSize = NSSize(width: 340, height: 430)
    static let compactSize = NSSize(width: 340, height: 142)
    static let railHitSize = NSSize(width: 20, height: 104)
    static let railVisualSize = NSSize(width: 6, height: 88)

    private enum Key {
        static let visible = "gaoyoujian.floating.visible"
        static let pinned = "gaoyoujian.floating.pinned"
        static let compact = "gaoyoujian.floating.compact"
        static let previews = "gaoyoujian.floating.showPreviews"
        static let opacity = "gaoyoujian.floating.opacity"
        static let display = "gaoyoujian.floating.display"
        static let horizontal = "gaoyoujian.floating.horizontalRatio"
        static let vertical = "gaoyoujian.floating.verticalRatio"
        static let edge = "gaoyoujian.floating.edge"
    }

    init(store: MailStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        savedVisible = defaults.object(forKey: Key.visible) as? Bool ?? true
        isPinned = defaults.object(forKey: Key.pinned) as? Bool ?? false
        isCompact = defaults.bool(forKey: Key.compact)
        showPreviews = defaults.bool(forKey: Key.previews)
        opacity = Self.safeOpacity(defaults.object(forKey: Key.opacity) as? Double ?? 1)
        rememberedDisplay = defaults.string(forKey: Key.display)
        let rememberedRatio = defaults.object(forKey: Key.vertical) as? Double ?? 0.15
        verticalRatio = rememberedRatio.isFinite ? min(max(rememberedRatio, 0), 1) : 0.15
        isOnLeft = defaults.string(forKey: Key.edge) == "left"
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminate), name: NSApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuTrackingBegan(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuTrackingEnded(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Call after the app's main-window and Settings actions have been connected.
    func restoreIfNeeded() {
        installMenuBarItemIfNeeded()
        guard !didRestoreVisibility else { return }
        didRestoreVisibility = true
        if savedVisible { show() }
    }

    func show() {
        installMenuBarItemIfNeeded()
        guard panel?.isPressed != true else { return }
        guard !NSScreen.screens.isEmpty else { return }
        let window = ensurePanel()
        isVisible = true
        isExpanded = true
        revealRequiresExit = false
        window.allowsKey = true
        window.isMovableByWindowBackground = false
        window.hasShadow = true
        window.contentView?.layer?.cornerRadius = 18
        applyRestoredFrame(to: window)
        window.level = .floating
        window.alphaValue = Self.safeOpacity(opacity)
        presentPanel(window)
        lastInsideAt = Date()
        startPointerWatcher()
        savedVisible = true
        defaults.set(true, forKey: Key.visible)
    }

    func hide() {
        panel?.cancelInteraction()
        panel?.orderOut(nil)
        stopPointerWatcher()
        isVisible = false
        isExpanded = false
        revealRequiresExit = false
        savedVisible = false
        persistPosition()
        defaults.set(false, forKey: Key.visible)
    }

    func toggle() { isVisible ? hide() : show() }

    /// Reveal the card from the tiny native edge hit window, without activating the application.
    func expand() {
        guard isVisible, let panel, !panel.isPressed else { return }
        if revealRequiresExit && panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) { return }
        revealRequiresExit = false
        lastInsideAt = Date()
        guard !isExpanded else { return }
        isExpanded = true
        panel.allowsKey = true
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.contentView?.layer?.cornerRadius = 18
        applyRestoredFrame(to: panel)
        presentPanel(panel)
    }

    func railPointerExited() {
        hoverStartedAt = nil
        guard let panel, !panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) else { return }
        revealRequiresExit = false
    }

    func railPointerEntered() {
        guard isVisible, !isExpanded, panel?.isPressed != true, !revealRequiresExit else { return }
        hoverStartedAt = Date()
    }

    /// Keep the feature enabled while replacing the actual window frame with its 20 × 104 hit area.
    func collapse() {
        guard isVisible, let panel, !panel.isPressed else { return }
        isExpanded = false
        panel.allowsKey = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = false
        panel.contentView?.layer?.cornerRadius = 0
        if panel.isKeyWindow { panel.resignKey() }
        applyRestoredFrame(to: panel)
        revealRequiresExit = panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        presentPanel(panel)
    }

    func setMenuOpen(_ open: Bool) {
        externalMenuOpen = open
        lastInsideAt = Date()
    }

    /// Called after the native mouse-up; moving the card and persisting its destination are separate operations.
    func snapToEdge() {
        guard let panel, !panel.isPressed, let screen = screenContaining(panel.frame) ?? preferredScreen() else { return }
        isOnLeft = Self.nearestEdgeIsLeft(for: panel.frame, in: screen.visibleFrame)
        rememberedDisplay = Self.displayIdentifier(screen)
        let available = max(screen.visibleFrame.height - Self.railHitSize.height, 0)
        verticalRatio = available > 0 ? Double((screen.visibleFrame.maxY - panel.frame.maxY) / available) : 0
        verticalRatio = min(max(verticalRatio, 0), 1)
        persistPosition()
        applyRestoredFrame(to: panel)
        lastInsideAt = Date()
    }

    func openInbox(accountID: UUID? = nil, messageID: String? = nil) {
        collapse()
        onOpenInbox?(accountID, messageID)
    }

    func compose(accountID: UUID? = nil) { collapse(); onCompose?(accountID) }
    func openSettings() { collapse(); onOpenSettings?() }

    func resetPosition() {
        guard panel?.isPressed != true else { return }
        defaults.removeObject(forKey: Key.display)
        defaults.removeObject(forKey: Key.horizontal)
        defaults.removeObject(forKey: Key.vertical)
        defaults.removeObject(forKey: Key.edge)
        rememberedDisplay = nil
        verticalRatio = 0.15
        isOnLeft = false
        if let panel { applyRestoredFrame(to: panel) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame, let panel, notification.object as? NSWindow === panel else { return }
        lastInsideAt = Date()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard !isApplyingFrame, let panel, notification.object as? NSWindow === panel else { return }
        lastInsideAt = Date()
    }

    func menuWillOpen(_ menu: NSMenu) {
        visibilityMenuItem?.title = isVisible ? "隐藏悬浮窗" : "显示悬浮窗"
    }

    private func installMenuBarItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "搞邮件")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "搞邮件"
        let menu = NSMenu()
        menu.delegate = self
        let visibility = NSMenuItem(title: isVisible ? "隐藏悬浮窗" : "显示悬浮窗", action: #selector(toggleFromMenu), keyEquivalent: "")
        visibility.target = self
        menu.addItem(visibility)
        visibilityMenuItem = visibility
        menu.addItem(.separator())
        for (title, action) in [("打开收件箱", #selector(openInboxFromMenu)), ("写邮件", #selector(composeFromMenu)), ("悬浮窗设置…", #selector(settingsFromMenu))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出搞邮件", action: #selector(quitFromMenu), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleFromMenu() { toggle() }
    @objc private func openInboxFromMenu() { openInbox() }
    @objc private func composeFromMenu() { compose() }
    @objc private func settingsFromMenu() { openSettings() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    @objc private func screensChanged() {
        guard let panel, !panel.isPressed else { return }
        // A remembered external display may have disappeared, so choose a connected screen first.
        applyRestoredFrame(to: panel)
    }

    @objc private func willTerminate() {
        persistPosition()
        stopPointerWatcher()
        // Do not call hide(): a visible panel should return on the next launch.
        defaults.set(isVisible, forKey: Key.visible)
    }

    @objc private func menuTrackingBegan(_ notification: Notification) {
        guard isVisible, let menu = notification.object as? NSMenu else { return }
        trackingMenus.insert(ObjectIdentifier(menu))
    }

    @objc private func menuTrackingEnded(_ notification: Notification) {
        if let menu = notification.object as? NSMenu { trackingMenus.remove(ObjectIdentifier(menu)) }
        lastInsideAt = Date()
    }

    private func startPointerWatcher() {
        guard pointerTimer == nil else { return }
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func stopPointerWatcher() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        trackingMenus.removeAll()
        externalMenuOpen = false
        hoverStartedAt = nil
    }

    private func checkPointer() {
        guard isVisible, let panel else { return }
        guard !panel.isPressed else { hoverStartedAt = nil; lastInsideAt = Date(); return }
        let inside = panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        if !isExpanded {
            if revealRequiresExit {
                if !inside { revealRequiresExit = false }
                return
            }
            if !inside { hoverStartedAt = nil; return }
            if hoverStartedAt == nil { hoverStartedAt = Date() }
            if let hoverStartedAt, Date().timeIntervalSince(hoverStartedAt) >= 0.28 { expand() }
            return
        }
        if inside || isPinned || externalMenuOpen || !trackingMenus.isEmpty || NSEvent.pressedMouseButtons != 0 || NSApp.modalWindow != nil {
            lastInsideAt = Date()
            return
        }
        if Date().timeIntervalSince(lastInsideAt) > 0.45 { collapse() }
    }

    private func ensurePanel() -> MailFloatingPanel {
        if let panel { return panel }
        let window = MailFloatingPanel(contentRect: NSRect(origin: .zero, size: desiredSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "搞邮件 · 悬浮窗"
        window.identifier = NSUserInterfaceItemIdentifier("GaoYouJian.Floating")
        window.delegate = self
        window.dismiss = { [weak self] in self?.collapse() }
        window.onPressChanged = { [weak self] _ in
            self?.hoverStartedAt = nil
            self?.lastInsideAt = Date()
        }
        window.onDrag = { [weak self] pointer, offset in self?.movePanel(pointer: pointer, grabOffset: offset) }
        window.onRelease = { [weak self] dragged in
            guard let self else { return }
            if dragged { self.snapToEdge() }
            else if !self.isExpanded { self.revealRequiresExit = false; self.expand() }
            if !self.isExpanded, let panel = self.panel {
                self.revealRequiresExit = panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
            }
            self.hoverStartedAt = nil
            self.lastInsideAt = Date()
        }
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.level = .floating
        window.alphaValue = opacity
        let hosting = MailFloatingHostingView(rootView: MailFloatingView(store: store, controller: self))
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 18
        hosting.layer?.masksToBounds = true
        window.contentView = hosting
        panel = window
        return window
    }

    private var desiredSize: NSSize { isExpanded ? (isCompact ? Self.compactSize : Self.expandedSize) : Self.railHitSize }

    private func presentPanel(_ panel: MailFloatingPanel) {
        #if DEBUG_TESTING
        // Hidden framework unit tests invoke the real state transitions without presenting a window.
        if suppressPanelPresentationForTesting { return }
        #endif
        panel.orderFrontRegardless()
    }

    private func applyRestoredFrame(to panel: NSWindow) {
        guard (panel as? MailFloatingPanel)?.isPressed != true else { return }
        guard let screen = preferredScreen() else { return }
        let connectedDisplay = Self.displayIdentifier(screen)
        if rememberedDisplay != connectedDisplay {
            rememberedDisplay = connectedDisplay
            persistPosition()
        }
        setFrame(Self.edgeFrame(size: desiredSize, in: screen.visibleFrame, isLeft: isOnLeft, verticalRatio: verticalRatio), on: panel)
    }

    private func movePanel(pointer: NSPoint, grabOffset: NSSize) {
        guard let panel, panel.isPressed,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? panel.screen ?? preferredScreen() else { return }
        setFrame(Self.draggingFrame(pointer: pointer, grabOffset: grabOffset, size: panel.frame.size, in: screen.visibleFrame), on: panel)
    }

    private func setFrame(_ frame: NSRect, on panel: NSWindow) {
        isApplyingFrame = true
        panel.setFrame(frame, display: true)
        isApplyingFrame = false
    }

    private func persistPosition() {
        defaults.set(rememberedDisplay, forKey: Key.display)
        defaults.set(isOnLeft ? "left" : "right", forKey: Key.edge)
        defaults.set(verticalRatio, forKey: Key.vertical)
        defaults.removeObject(forKey: Key.horizontal)
    }

    private func preferredScreen() -> NSScreen? {
        if let identifier = rememberedDisplay,
           let screen = NSScreen.screens.first(where: { Self.displayIdentifier($0) == identifier }) { return screen }
        return NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func screenContaining(_ frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            let l = lhs.frame.intersection(frame), r = rhs.frame.intersection(frame)
            return max(0, l.width) * max(0, l.height) < max(0, r.width) * max(0, r.height)
        }
    }

    private static func displayIdentifier(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value)) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    static func safeOpacity(_ value: Double) -> Double { value.isFinite ? min(max(value, 0.65), 1) : 1 }

    static func nearestEdgeIsLeft(for frame: NSRect, in visible: NSRect) -> Bool { frame.midX < visible.midX }

    /// Dragging follows the pointer freely; edge snapping is intentionally deferred until mouse-up.
    static func draggingFrame(pointer: NSPoint, grabOffset: NSSize, size: NSSize, in visible: NSRect) -> NSRect {
        let width = min(max(size.width, 1), max(visible.width, 1))
        let height = min(max(size.height, 1), max(visible.height, 1))
        let x = min(max(pointer.x - grabOffset.width, visible.minX), visible.maxX - width)
        let y = min(max(pointer.y - grabOffset.height, visible.minY), visible.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Both forms use the rail's top anchor, so a reveal keeps the user's pointer inside the card.
    static func edgeFrame(size: NSSize, in visible: NSRect, isLeft: Bool, verticalRatio: Double) -> NSRect {
        let ratio = verticalRatio.isFinite ? min(max(verticalRatio, 0), 1) : 0.15
        let width = min(max(size.width, 1), max(visible.width, 1))
        let height = min(max(size.height, 1), max(visible.height, 1))
        let railHeight = min(railHitSize.height, max(visible.height, 1))
        let top = visible.maxY - CGFloat(ratio) * max(visible.height - railHeight, 0)
        let y = min(max(top - height, visible.minY), visible.maxY - height)
        let x = isLeft ? visible.minX : visible.maxX - width
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Pure geometry shared by the controller and its isolated tests.
    static func clamped(_ requested: NSRect, in visible: NSRect) -> NSRect {
        let usable = visible.insetBy(dx: min(margin, max(0, visible.width / 4)), dy: min(margin, max(0, visible.height / 4)))
        let width = min(max(requested.width, 1), max(usable.width, 1))
        let height = min(max(requested.height, 1), max(usable.height, 1))
        let x = min(max(requested.minX, usable.minX), usable.maxX - width)
        let y = min(max(requested.minY, usable.minY), usable.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class MailFloatingHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Register the empty header area; action buttons remain outside these native grab regions.
struct MailFloatingDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { view.registerDragArea() }

    final class DragView: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); registerDragArea() }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        func registerDragArea() { (window as? MailFloatingPanel)?.dragHandles.add(self) }
    }
}
