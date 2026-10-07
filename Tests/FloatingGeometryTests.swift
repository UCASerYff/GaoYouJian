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
        let defaults = UserDefaults(suiteName:suite)!
        defaults.set(0.2,forKey:"gaoyoujian.floating.verticalRatio")
        defaults.set("right",forKey:"gaoyoujian.floating.edge")
        defaults.set(true,forKey:"gaoyoujian.floating.pinned")
        defaults.set(true,forKey:"gaoyoujian.floating.compact")
        let controller = MailFloatingController(store:MailStore(),defaults:defaults)
        controller.suppressPanelPresentationForTesting = true
        controller.restoreIfNeeded()
        let panel = controller.ensurePanel()
        let otherWindow = NSWindow(contentRect:NSRect(x:100,y:100,width:400,height:250),styleMask:[.titled],backing:.buffered,defer:false)
        otherWindow.isReleasedWhenClosed = false
        defer {
            controller.hide()
            panel.delegate = nil
            panel.contentView = nil
            panel.close()
            otherWindow.close()
            defaults.removePersistentDomain(forName:suite)
            _ = defaults.synchronize()
            let preferenceFile = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences",isDirectory:true).appendingPathComponent(suite + ".plist")
            if FileManager.default.fileExists(atPath:preferenceFile.path) { try? FileManager.default.removeItem(at:preferenceFile) }
            verify(defaults.persistentDomain(forName:suite)?.isEmpty != false && !FileManager.default.fileExists(atPath:preferenceFile.path), "random native test preference domain and its empty plist are removed")
            print("Hidden native framework: \(nativeChecks) checks passed; no window presentation or OS input injection")
        }
        let base = Date()
        let outside = NSPoint(x:screen.visibleFrame.minX-10,y:screen.visibleFrame.minY-10)
        func evaluate(_ point:NSPoint,_ seconds:Double) { controller.evaluatePointer(pointer:point,now:base.addingTimeInterval(seconds)) }
        func reveal(_ seconds:Double) {
            controller.revealRequiresExit = false
            controller.expand(pointer:outside,now:base.addingTimeInterval(seconds))
        }
        var eventNumber = 0
        func event(_ type:NSEvent.EventType,at point:NSPoint,in window:NSWindow? = nil,modifiers:NSEvent.ModifierFlags = []) -> NSEvent {
            eventNumber += 1
            let target = window ?? panel
            return NSEvent.mouseEvent(with:type,location:target.convertPoint(fromScreen:point),modifierFlags:modifiers,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:target.windowNumber,context:nil,eventNumber:eventNumber,clickCount:1,pressure:type == .leftMouseUp ? 0 : 1)!
        }
        verify(!panel.isVisible && controller.isVisible && !controller.isExpanded && panel.frame.size == railHitSize && !panel.allowsKey && !panel.hasShadow && panel.level == .floating && controller.statusItem == nil && defaults.bool(forKey:"gaoyoujian.floating.pinned") && defaults.bool(forKey:"gaoyoujian.floating.compact"), "restore starts hidden small rail and ignores obsolete true preferences")
        let monitorCount = controller.eventMonitors.count
        controller.startMouseObservers()
        verify(monitorCount == 0 && controller.eventMonitors.isEmpty && controller.pointerTimer?.timeInterval == pointerInterval, "hidden tests subscribe to no user events while retaining the actual precise polling configuration")
        let railCenter = NSPoint(x:panel.frame.midX,y:panel.frame.midY)
        evaluate(railCenter,0); evaluate(railCenter,0.2)
        verify(!controller.isExpanded, "rail hover waits for reveal delay")
        evaluate(railCenter,0.29)
        verify(controller.isExpanded && panel.frame.size == expandedSize && !panel.isVisible, "hover expands a short native card without a 430 pt first frame")
        let inside = NSPoint(x:panel.frame.midX,y:panel.frame.midY)
        evaluate(inside,1); evaluate(outside,1.1); evaluate(outside,1.17)
        verify(controller.isExpanded, "leave deadline starts at first actual outside sample")
        evaluate(outside,1.19)
        verify(!controller.isExpanded && panel.frame.size == railHitSize, "outside sample plus 80 ms promptly collapses the card")
        reveal(2)
        let transparentCorner = NSPoint(x:panel.frame.minX+1,y:panel.frame.maxY-1)
        evaluate(transparentCorner,2.1); evaluate(transparentCorner,2.19)
        verify(!controller.isExpanded, "transparent circular corner is an outside pointer region")
        reveal(3)
        let onePointOutside = NSPoint(x:panel.frame.minX-1,y:panel.frame.midY)
        evaluate(onePointOutside,3.1); evaluate(onePointOutside,3.19)
        verify(!controller.isExpanded, "one point outside the native card is not expanded by an invisible margin")
        reveal(4)
        let unrelatedMenu = NSMenu()
        controller.menuTrackingBegan(Notification(name:NSMenu.didBeginTrackingNotification,object:unrelatedMenu))
        evaluate(outside,4.1); evaluate(outside,4.19)
        verify(controller.trackingMenus.isEmpty && !controller.isExpanded, "main app and status menus cannot hold the floating card open")
        reveal(5)
        let host = panel.contentView!
        let menuRegion = MailFloatingMenuRegion.MenuRegionView(frame:NSRect(x:10,y:host.bounds.height-55,width:280,height:29))
        host.addSubview(menuRegion); menuRegion.registerMenuArea()
        let menuPoint = panel.convertPoint(toScreen:menuRegion.convert(NSPoint(x:40,y:14),to:nil))
        controller.notePanelMouseDown(event(.leftMouseDown,at:menuPoint))
        let menu = NSMenu()
        controller.menuTrackingBegan(Notification(name:NSMenu.didBeginTrackingNotification,object:menu))
        let childMenu = NSMenu()
        let childItem = NSMenuItem(title:"Test",action:nil,keyEquivalent:"")
        menu.addItem(childItem); childItem.submenu = childMenu
        controller.menuTrackingBegan(Notification(name:NSMenu.didBeginTrackingNotification,object:childMenu))
        evaluate(outside,5.1); evaluate(outside,9)
        let protectedMenu = controller.isExpanded && controller.trackingMenus.count == 2
        let menuItemEvent = NSEvent.mouseEvent(with:.leftMouseDown,location:outside,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        let returnedMenuEvent = controller.observeLocalMouseEvent(menuItemEvent)
        verify(protectedMenu && controller.isExpanded && returnedMenuEvent === menuItemEvent, "only registered picker tracking protects menu-item clicks and returns the original event")
        controller.menuTrackingEnded(Notification(name:NSMenu.didEndTrackingNotification,object:menu))
        evaluate(outside,10); evaluate(outside,10.09)
        verify(!controller.isExpanded && controller.trackingMenus.isEmpty && controller.rootTrackingMenu == nil, "menu ending clears the guard and promptly resumes outside collapse")
        reveal(11)
        let insideEvent = event(.leftMouseDown,at:NSPoint(x:panel.frame.midX,y:panel.frame.midY))
        let returnedInsideEvent = controller.observeLocalMouseEvent(insideEvent)
        verify(insideEvent.window === panel && returnedInsideEvent === insideEvent && controller.isExpanded, "own native card click uses its event coordinate and preserves original event identity")
        let otherEvent = event(.leftMouseDown,at:inside,in:otherWindow)
        _ = controller.observeLocalMouseEvent(otherEvent)
        verify(otherEvent.window === otherWindow && !controller.isExpanded, "another app window is outside even when its screen coordinate overlaps the card")
        reveal(12)
        controller.notePanelMouseDown(event(.leftMouseDown,at:panel.convertPoint(toScreen:menuRegion.convert(NSPoint(x:40,y:14),to:nil))))
        controller.menuTrackingBegan(Notification(name:NSMenu.didBeginTrackingNotification,object:menu))
        controller.observeMouseEvent(menuItemEvent,isGlobal:true)
        verify(!controller.isExpanded && controller.trackingMenus.isEmpty && controller.pendingMailboxMenuUntil == nil, "other-app mouse-down immediately collapses and clears obsolete menu ownership")
        reveal(12.1)
        controller.notePanelMouseDown(event(.leftMouseDown,at:panel.convertPoint(toScreen:menuRegion.convert(NSPoint(x:40,y:14),to:nil))))
        controller.menuTrackingBegan(Notification(name:NSMenu.didBeginTrackingNotification,object:menu))
        let cornerEvent = event(.leftMouseDown,at:NSPoint(x:panel.frame.minX+1,y:panel.frame.maxY-1))
        _ = controller.observeLocalMouseEvent(cornerEvent)
        verify(!controller.isExpanded && controller.trackingMenus.isEmpty, "a card's transparent corner is outside even while its menu has been tracking")
        reveal(13)
        let first = MailFloatingDragHandle.DragView(frame:NSRect(x:16,y:host.bounds.height-18,width:80,height:8))
        let second = MailFloatingDragHandle.DragView(frame:NSRect(x:105,y:host.bounds.height-18,width:55,height:8))
        host.addSubview(first); host.addSubview(second)
        first.registerDragArea(); second.registerDragArea()
        let initial = panel.frame
        let firstGlobal = panel.convertPoint(toScreen:first.convert(NSPoint(x:20,y:4),to:nil))
        panel.sendEvent(event(.leftMouseDown,at:firstGlobal))
        controller.collapse(); controller.resetPosition(); evaluate(outside,100)
        controller.updateExpandedHeight(392)
        verify(panel.isPressed && controller.isExpanded && panel.frame == initial && controller.expandedHeight == 280, "actual header press blocks leave and defers dynamic resize while dragging")
        panel.sendEvent(event(.leftMouseUp,at:firstGlobal))
        verify(!panel.isPressed && panel.frame.height == 392 && controller.expandedHeight == 392, "native mouse-up releases the guard and applies requested content height")
        controller.updateExpandedHeight(280)
        let secondGlobal = panel.convertPoint(toScreen:second.convert(NSPoint(x:15,y:4),to:nil))
        let dragInitial = panel.frame
        panel.sendEvent(event(.leftMouseDown,at:secondGlobal))
        let beforeRatio = defaults.double(forKey:"gaoyoujian.floating.verticalRatio")
        let offset = NSSize(width:secondGlobal.x-dragInitial.minX,height:secondGlobal.y-dragInitial.minY)
        let movedGlobal = NSPoint(x:screen.visibleFrame.minX+30+offset.width,y:screen.visibleFrame.minY+80+offset.height)
        panel.sendEvent(event(.leftMouseDragged,at:movedGlobal))
        let wanted = draggingFrame(pointer:movedGlobal,grabOffset:offset,size:dragInitial.size,in:screen.visibleFrame)
        verify(panel.frame == wanted && panel.isPressed && defaults.double(forKey:"gaoyoujian.floating.verticalRatio") == beforeRatio && defaults.string(forKey:"gaoyoujian.floating.edge") == "right", "native drag follows original offset and never persists before release")
        panel.sendEvent(event(.leftMouseUp,at:movedGlobal))
        verify(!panel.isPressed && controller.isOnLeft && panel.frame.minX == screen.visibleFrame.minX && defaults.string(forKey:"gaoyoujian.floating.edge") == "left" && defaults.double(forKey:"gaoyoujian.floating.verticalRatio") != beforeRatio, "native release snaps and persists destination")
        let saved = panel.frame
        controller.collapse(pointer:outside,now:base.addingTimeInterval(110)); reveal(111)
        let controlPoint = panel.convertPoint(toScreen:first.convert(NSPoint(x:20,y:4),to:nil))
        let businessPoint = panel.convertPoint(toScreen:NSPoint(x:panel.frame.width-16,y:30))
        verify(panel.frame == saved && !panel.isGrabEvent(event(.leftMouseDown,at:controlPoint,modifiers:[.control])) && !panel.isGrabEvent(event(.leftMouseDown,at:businessPoint)), "collapse restores release position and never captures business/control-click regions")
        panel.sendEvent(event(.leftMouseDown,at:controlPoint))
        controller.observeMouseEvent(menuItemEvent,isGlobal:true)
        verify(!panel.isPressed && !controller.isExpanded, "fresh external mouse-down clears an old unmatched press before immediate collapse")
        reveal(112)
        panel.sendEvent(event(.leftMouseDown,at:controlPoint))
        controller.observeMouseEvent(event(.leftMouseUp,at:outside,in:otherWindow),isGlobal:false)
        verify(!panel.isPressed && controller.isExpanded, "a release routed to another native window cannot leave drag protection latched")
        controller.notePanelMouseDown(event(.leftMouseDown,at:panel.convertPoint(toScreen:menuRegion.convert(NSPoint(x:40,y:14),to:nil))))
        controller.menuTrackingBegan(Notification(name:NSMenu.didBeginTrackingNotification,object:menu))
        let escape = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:panel.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        panel.keyDown(with:escape)
        verify(!controller.isExpanded && !panel.isPressed && controller.trackingMenus.isEmpty, "Escape clears owned menu state and collapses without disabling the feature")
        controller.collapse(pointer:outside,now:base.addingTimeInterval(120))
        let railStart = panel.frame
        let railPoint = panel.convertPoint(toScreen:NSPoint(x:10,y:50))
        panel.sendEvent(event(.leftMouseDown,at:railPoint))
        controller.railPointerEntered(); controller.expand(); evaluate(railPoint,200)
        verify(panel.isPressed && !controller.isExpanded && panel.frame == railStart, "native rail press prevents reveal and keeps small physical hit window")
        let railBeforeRatio = defaults.double(forKey:"gaoyoujian.floating.verticalRatio")
        let railTarget = NSPoint(x:screen.visibleFrame.maxX-70,y:screen.visibleFrame.minY+160)
        panel.sendEvent(event(.leftMouseDragged,at:railTarget))
        let noEarlySave = defaults.double(forKey:"gaoyoujian.floating.verticalRatio") == railBeforeRatio
        panel.sendEvent(event(.leftMouseUp,at:railTarget))
        verify(noEarlySave && !panel.isPressed && !panel.isVisible && !controller.isExpanded && panel.frame.size == railHitSize && !controller.isOnLeft && panel.frame.maxX == screen.visibleFrame.maxX && defaults.string(forKey:"gaoyoujian.floating.edge") == "right", "native rail drag release preserves tiny form and saves its new edge")
        reveal(210)
        controller.updateExpandedHeight(1000)
        let heightLimit = min(420,screen.visibleFrame.height)
        verify(controller.expandedHeight == heightLimit && panel.frame.height == heightLimit && !panel.isVisible, "natural card height clamps real native frame to screen and 420 pt")
        controller.hide()
        verify(controller.eventMonitors.isEmpty && controller.pointerTimer == nil && controller.trackingMenus.isEmpty && !controller.isVisible, "disable removes observers, timer and stale menu protection")
        controller.show()
        verify(!panel.isVisible && !controller.isExpanded && panel.frame.size == railHitSize && controller.eventMonitors.count == monitorCount, "hidden re-enable starts rail without subscribing to user events")
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
                    check(screen.contains(rail) && screen.contains(card), "all forms fit screen")
                    check(card.contains(rail), "hover pointer stays inside revealed card")
                    check(left ? rail.minX == screen.minX : rail.maxX == screen.maxX, "rail touches remembered edge")
                    check(left ? card.minX == screen.minX : card.maxX == screen.maxX, "card shares rail edge")
                }
            }
        }
        let screen = screens[0]
        let hitFrame = NSRect(x:-340,y:50,width:340,height:280)
        check(MailFloatingController.roundedCardContains(NSPoint(x:hitFrame.midX,y:hitFrame.midY),in:hitFrame), "visible card center is interactive")
        check(MailFloatingController.roundedCardContains(NSPoint(x:hitFrame.minX,y:hitFrame.midY),in:hitFrame), "straight visible edge is included without a margin")
        check(!MailFloatingController.roundedCardContains(NSPoint(x:hitFrame.minX-1,y:hitFrame.midY),in:hitFrame), "outside one point is excluded")
        for corner in [NSPoint(x:hitFrame.minX+1,y:hitFrame.minY+1),NSPoint(x:hitFrame.maxX-1,y:hitFrame.minY+1),NSPoint(x:hitFrame.minX+1,y:hitFrame.maxY-1),NSPoint(x:hitFrame.maxX-1,y:hitFrame.maxY-1)] {
            check(!MailFloatingController.roundedCardContains(corner,in:hitFrame), "all transparent rounded corners are outside")
        }
        check(MailFloatingController.safeExpandedHeight(279.2,availableHeight:900) == 280 && MailFloatingController.safeExpandedHeight(1000,availableHeight:900) == 420 && MailFloatingController.safeExpandedHeight(300,availableHeight:220) == 220, "natural height rounds and clamps to the real screen limit")
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
