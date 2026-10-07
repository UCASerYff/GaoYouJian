import AppKit
import SwiftUI

/// Only the small native window remains when collapsed; no invisible full-card region blocks other apps.
struct MailFloatingRailView: View {
    @ObservedObject var controller: MailFloatingController
    var unreadCount: Int = 0
    var errorCount: Int = 0

    private var color: Color { errorCount > 0 ? .orange : unreadCount > 0 ? .indigo : .secondary }

    var body: some View {
        Button(action: controller.expand) {
            Capsule(style: .continuous)
                .fill(color.opacity(errorCount > 0 || unreadCount > 0 ? 0.9 : 0.55))
                .frame(width: MailFloatingController.railVisualSize.width, height: MailFloatingController.railVisualSize.height)
                .frame(width: MailFloatingController.railHitSize.width, height: MailFloatingController.railHitSize.height, alignment: controller.isOnLeft ? .leading : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MailFloatingRailTrackingView(onEnter: { controller.expand() }, onExit: { controller.railPointerExited() }).accessibilityHidden(true))
        .accessibilityLabel(errorCount > 0 ? "搞邮件，邮箱待检查" : unreadCount > 0 ? "搞邮件，有缓存未读邮件" : "搞邮件悬浮窗")
    }
}

private struct MailFloatingRailTrackingView: NSViewRepresentable {
    var onEnter: () -> Void
    var onExit: () -> Void
    func makeNSView(context: Context) -> TrackingView { let view = TrackingView(); view.onEnter = onEnter; view.onExit = onExit; return view }
    func updateNSView(_ view: TrackingView, context: Context) { view.onEnter = onEnter; view.onExit = onExit }

    final class TrackingView: NSView {
        var onEnter: (() -> Void)?
        var onExit: (() -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { onEnter?() }
        override func mouseExited(with event: NSEvent) { onExit?() }
        override func mouseDown(with event: NSEvent) { onEnter?() }
    }
}
