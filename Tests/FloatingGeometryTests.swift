import AppKit
import SwiftUI
// Inert app types keep native framework tests independent of mail accounts, credentials, and production data.
@MainActor final class MailStore {}
struct MailFloatingView: View {
    let store: MailStore
    @ObservedObject var controller: MailFloatingController
    var body: some View {
        if controller.isExpanded { Text("Test").frame(maxWidth:.infinity,maxHeight:.infinity) }
        else { MailFloatingRailView(controller:controller) }
    }
}

#if DEBUG_TESTING
extension MailFloatingController {
    static func runHiddenNativeChecks(_ check: (Bool, String) -> Void) {
        _ = NSApplication.shared.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            print("Hidden native framework: skipped (no display)")
            return
        }
        var nativeChecks = 0
        func verify(_ value: Bool, _ name: String) { nativeChecks += 1; check(value, name) }
        let suite = "GaoYouJian.HiddenNativeTest." + UUID().uuidString
        if let metadata = ProcessInfo.processInfo.environment["GAOYOUJIAN_TEST_SUITE_METADATA"] {
            try? (suite + "\n").write(to:URL(fileURLWithPath:metadata),atomically:true,encoding:.utf8)
        }
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(0.2, forKey: "gaoyoujian.floating.verticalRatio")
        defaults.set("right", forKey: "gaoyoujian.floating.edge")
        let controller = MailFloatingController(store: MailStore(), defaults: defaults)
        controller.suppressPanelPresentationForTesting = true
        controller.isPinned = true
        controller.isVisible = true
        controller.isExpanded = true
        let panel = controller.ensurePanel()
        controller.applyRestoredFrame(to: panel)
        defer {
            panel.cancelInteraction()
            panel.delegate = nil
            panel.contentView = nil
            panel.close()
            defaults.removePersistentDomain(forName: suite)
            _ = defaults.synchronize()
            let preferenceFile = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences", isDirectory:true).appendingPathComponent(suite + ".plist")
            if FileManager.default.fileExists(atPath:preferenceFile.path) { try? FileManager.default.removeItem(at:preferenceFile) }
            verify(defaults.persistentDomain(forName: suite)?.isEmpty != false && !FileManager.default.fileExists(atPath:preferenceFile.path), "random native test preference domain and its empty plist are removed")
            print("Hidden native framework: \(nativeChecks) checks passed; no window presentation or OS input injection")
        }
        verify(!panel.isVisible && panel.level == .floating && panel.styleMask.contains(.nonactivatingPanel), "real native panel starts hidden with production style and level")
        let host = panel.contentView!
        let first = MailFloatingDragHandle.DragView(frame: NSRect(x:16,y:host.bounds.height-44,width:80,height:28))
        let second = MailFloatingDragHandle.DragView(frame: NSRect(x:105,y:host.bounds.height-44,width:55,height:28))
        host.addSubview(first); host.addSubview(second)
        first.registerDragArea(); second.registerDragArea()
        var eventNumber = 0
        func event(_ type: NSEvent.EventType, at point: NSPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            eventNumber += 1
            return NSEvent.mouseEvent(with:type,location:panel.convertPoint(fromScreen:point),modifierFlags:modifiers,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,context:nil,eventNumber:eventNumber,clickCount:1,pressure:type == .leftMouseUp ? 0 : 1)!
        }
        let initial = panel.frame
        let firstPoint = first.convert(NSPoint(x:20,y:14), to:nil)
        let firstGlobal = panel.convertPoint(toScreen:firstPoint)
        panel.sendEvent(event(.leftMouseDown,at:firstGlobal))
        verify(panel.isPressed, "native sendEvent captures the first registered header region")
        controller.collapse(); controller.resetPosition(); controller.checkPointer()
        verify(controller.isExpanded && panel.frame == initial, "native press blocks collapse reset and pointer polling")
        panel.sendEvent(event(.leftMouseUp,at:firstGlobal))
        verify(!panel.isPressed && panel.frame == initial, "native click releases without moving or snapping")
        let secondGlobal = panel.convertPoint(toScreen:second.convert(NSPoint(x:15,y:14),to:nil))
        panel.sendEvent(event(.leftMouseDown,at:secondGlobal))
        verify(panel.isPressed, "native sendEvent captures a second registered header region")
        let beforeRatio = defaults.double(forKey:"gaoyoujian.floating.verticalRatio")
        let offset = NSSize(width:secondGlobal.x-initial.minX,height:secondGlobal.y-initial.minY)
        let movedGlobal = NSPoint(x:screen.visibleFrame.minX+30+offset.width,y:screen.visibleFrame.minY+80+offset.height)
        panel.sendEvent(event(.leftMouseDragged,at:movedGlobal))
        let wanted = draggingFrame(pointer:movedGlobal,grabOffset:offset,size:initial.size,in:screen.visibleFrame)
        verify(panel.frame == wanted && panel.isPressed && controller.isPinned, "real pinned panel follows native drag while the press remains active")
        verify(defaults.double(forKey:"gaoyoujian.floating.verticalRatio") == beforeRatio && defaults.string(forKey:"gaoyoujian.floating.edge") == "right", "native drag does not persist before mouse-up")
        panel.sendEvent(event(.leftMouseUp,at:movedGlobal))
        verify(!panel.isPressed && controller.isOnLeft && panel.frame.minX == screen.visibleFrame.minX, "native mouse-up invokes the real left-edge release callback")
        verify(defaults.string(forKey:"gaoyoujian.floating.edge") == "left" && defaults.double(forKey:"gaoyoujian.floating.verticalRatio") != beforeRatio, "native release persists the changed edge and height")
        let saved = panel.frame
        let controlPoint = panel.convertPoint(toScreen:first.convert(NSPoint(x:20,y:14),to:nil))
        let buttonPoint = panel.convertPoint(toScreen:NSPoint(x:panel.frame.width-16,y:panel.frame.height-30))
        verify(!panel.isGrabEvent(event(.leftMouseDown,at:controlPoint,modifiers:[.control])) && !panel.isGrabEvent(event(.leftMouseDown,at:buttonPoint)), "control-click and the right-side action-button region are not captured for dragging")
        controller.collapse()
        verify(!panel.isVisible && controller.isVisible && !controller.isExpanded && panel.frame.size == railHitSize, "real collapse retains feature state and shrinks the hidden native window")
        controller.revealRequiresExit = false
        controller.expand()
        verify(!panel.isVisible && controller.isExpanded && panel.frame == saved, "real expansion restores the released card position without showing it")
        controller.collapse()
        let railStart = panel.frame
        let railPoint = panel.convertPoint(toScreen:NSPoint(x:10,y:50))
        panel.sendEvent(event(.leftMouseDown,at:railPoint))
        controller.railPointerEntered(); controller.expand(); controller.checkPointer()
        verify(panel.isPressed && !controller.isExpanded && panel.frame == railStart, "native rail press prevents hover expansion")
        let railBeforeRatio = defaults.double(forKey:"gaoyoujian.floating.verticalRatio")
        let railTarget = NSPoint(x:screen.visibleFrame.maxX-70,y:screen.visibleFrame.minY+160)
        panel.sendEvent(event(.leftMouseDragged,at:railTarget))
        verify(panel.frame.size == railHitSize && panel.isPressed && !controller.isExpanded && defaults.double(forKey:"gaoyoujian.floating.verticalRatio") == railBeforeRatio, "native rail dragging keeps its small hit frame and defers persistence")
        panel.sendEvent(event(.leftMouseUp,at:railTarget))
        verify(!panel.isPressed && !panel.isVisible && !controller.isExpanded && !controller.isOnLeft && panel.frame.maxX == screen.visibleFrame.maxX && defaults.string(forKey:"gaoyoujian.floating.edge") == "right", "native rail release snaps and saves the right edge without opening a window")
        let railSavedRatio = defaults.double(forKey:"gaoyoujian.floating.verticalRatio")
        controller.revealRequiresExit = false
        controller.expand()
        let restored = panel.frame
        controller.applyRestoredFrame(to:panel)
        verify(!panel.isVisible && restored == panel.frame && defaults.double(forKey:"gaoyoujian.floating.verticalRatio") == railSavedRatio, "repeated layout preserves the native release height without presenting the panel")
    }
}
#endif
@main @MainActor struct EdgeGeometryTests {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ name: String) { precondition(value, name); checks += 1 }
        check(MailFloatingController.railHitSize == NSSize(width:20,height:104), "actual hidden hit size")
        check(MailFloatingController.railVisualSize == NSSize(width:6,height:88), "visual hidden size")
        let screens = [NSRect(x:0,y:0,width:1440,height:900),NSRect(x:-1920,y:-1080,width:1920,height:1080),NSRect(x:100,y:300,width:320,height:220),NSRect(x:0,y:0,width:20,height:60)]
        for screen in screens {
            for left in [false,true] {
                for ratio in [0.0,0.15,0.5,1.0] {
                    let rail = MailFloatingController.edgeFrame(size:MailFloatingController.railHitSize,in:screen,isLeft:left,verticalRatio:ratio)
                    let card = MailFloatingController.edgeFrame(size:MailFloatingController.expandedSize,in:screen,isLeft:left,verticalRatio:ratio)
                    let compact = MailFloatingController.edgeFrame(size:MailFloatingController.compactSize,in:screen,isLeft:left,verticalRatio:ratio)
                    check(screen.contains(rail) && screen.contains(card) && screen.contains(compact), "all forms fit screen")
                    check(card.contains(rail) && compact.contains(rail), "hover pointer stays inside revealed card")
                    check(left ? rail.minX == screen.minX : rail.maxX == screen.maxX, "rail touches remembered edge")
                    check(left ? card.minX == screen.minX : card.maxX == screen.maxX, "card shares rail edge")
                }
            }
        }
        let screen = screens[0]
        check(MailFloatingController.edgeFrame(size:MailFloatingController.railHitSize,in:screen,isLeft:false,verticalRatio:-4) == MailFloatingController.edgeFrame(size:MailFloatingController.railHitSize,in:screen,isLeft:false,verticalRatio:0), "negative ratio clamped")
        check(MailFloatingController.edgeFrame(size:MailFloatingController.railHitSize,in:screen,isLeft:false,verticalRatio:4) == MailFloatingController.edgeFrame(size:MailFloatingController.railHitSize,in:screen,isLeft:false,verticalRatio:1), "large ratio clamped")
        check(MailFloatingController.edgeFrame(size:MailFloatingController.railHitSize,in:screen,isLeft:false,verticalRatio:.nan) == MailFloatingController.edgeFrame(size:MailFloatingController.railHitSize,in:screen,isLeft:false,verticalRatio:0.15), "invalid ratio safely defaults")
        check(MailFloatingController.nearestEdgeIsLeft(for:NSRect(x:20,y:20,width:340,height:430),in:screen), "drag snaps left")
        check(!MailFloatingController.nearestEdgeIsLeft(for:NSRect(x:1000,y:20,width:340,height:430),in:screen), "drag snaps right")
        check(MailFloatingController.safeOpacity(-1) == 0.65 && MailFloatingController.safeOpacity(2) == 1 && MailFloatingController.safeOpacity(.nan) == 1, "opacity remains visible")
        var session = MailFloatingDragSession()
        let original = NSRect(x:400,y:200,width:340,height:430)
        let press = NSPoint(x:440,y:520)
        check(session.finish() == nil, "an unpressed session cannot release")
        check(session.carry(pointer:press) == nil, "drag event without mouse-down does nothing")
        session.begin(pointer:press,frame:original)
        check(session.isPressed && !session.didDrag, "mouse-down remains pressed until mouse-up")
        check(session.carry(pointer:NSPoint(x:443,y:520)) == nil, "small pointer jitter does not move the window")
        check(session.isPressed && !session.didDrag, "a request or jitter cannot be mistaken for mouse-up")
        check(session.finish() == false && !session.isPressed, "a click finishes without recording a drag")
        session.begin(pointer:press,frame:original)
        check(session.carry(pointer:NSPoint(x:444,y:520)) == NSSize(width:40,height:320), "native drag threshold retains the grab offset")
        check(session.isPressed && session.didDrag, "dragging remains pressed")
        let pointer = NSPoint(x:600,y:430)
        let grab = session.carry(pointer:pointer)!
        let free = MailFloatingController.draggingFrame(pointer:pointer,grabOffset:grab,size:original.size,in:screen)
        check(free.origin == NSPoint(x:560,y:110), "dragging follows pointer with original grab offset")
        check(free.minX != screen.minX && free.maxX != screen.maxX, "dragging is not snapped before mouse-up")
        check(session.carry(pointer:NSPoint(x:610,y:450)) == grab, "continued events retain the same grab offset")
        check(session.finish() == true && !session.isPressed && !session.didDrag, "only mouse-up completes the drag")
        check(session.finish() == nil, "a duplicate release cannot save twice")
        session.begin(pointer:press,frame:original)
        check(!session.didDrag, "the next gesture starts with fresh movement state")
        _ = session.finish()
        let external = screens[1]
        let externalFrame = MailFloatingController.draggingFrame(pointer:NSPoint(x:-1700,y:-300),grabOffset:grab,size:original.size,in:external)
        check(externalFrame.origin == NSPoint(x:-1740,y:-620), "dragging works on a display with negative coordinates")
        let limited = MailFloatingController.draggingFrame(pointer:NSPoint(x:-5000,y:-5000),grabOffset:grab,size:original.size,in:external)
        check(external.contains(limited) && limited.origin == external.origin, "dragging stays reachable at display boundaries")
        let oversized = MailFloatingController.draggingFrame(pointer:press,grabOffset:grab,size:NSSize(width:3000,height:3000),in:external)
        check(oversized == external, "oversized windows fit the target display while dragging")
        #if DEBUG_TESTING
        MailFloatingController.runHiddenNativeChecks(check)
        #endif
        print("Floating state, geometry and native framework: \(checks) assertions passed")
    }
}
