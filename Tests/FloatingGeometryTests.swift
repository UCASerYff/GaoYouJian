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
        do {
            defaults.set("left",forKey:"gaoyoujian.floating.edge")
            defaults.set("legacy-display-test",forKey:"gaoyoujian.floating.display")
            let legacy = MailFloatingController(store:MailStore(),defaults:defaults)
            verify(legacy.dockMode == .left && legacy.isOnLeft && legacy.verticalRatio == 0.2 && legacy.rememberedDisplay == "legacy-display-test" && defaults.object(forKey:"gaoyoujian.floating.dockMode") == nil, "legacy edge, height and display migrate in memory without wiping prior preferences")
            defaults.set("right",forKey:"gaoyoujian.floating.edge")
            defaults.removeObject(forKey:"gaoyoujian.floating.display")
        }
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
        func closeFrame(_ a:NSRect,_ b:NSRect) -> Bool { abs(a.minX-b.minX) < 0.01 && abs(a.minY-b.minY) < 0.01 && abs(a.width-b.width) < 0.01 && abs(a.height-b.height) < 0.01 }
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
        NotificationCenter.default.post(name:NSMenu.didBeginTrackingNotification,object:NSMenu())
        evaluate(outside,4.1); evaluate(outside,4.19)
        verify(!controller.isExpanded, "unrelated app menus cannot hold the floating card open after removal of the mailbox picker")
        reveal(11)
        let insideEvent = event(.leftMouseDown,at:NSPoint(x:panel.frame.midX,y:panel.frame.midY))
        let returnedInsideEvent = controller.observeLocalMouseEvent(insideEvent)
        verify(insideEvent.window === panel && returnedInsideEvent === insideEvent && controller.isExpanded, "own native card click uses its event coordinate and preserves original event identity")
        let otherEvent = event(.leftMouseDown,at:inside,in:otherWindow)
        _ = controller.observeLocalMouseEvent(otherEvent)
        verify(otherEvent.window === otherWindow && !controller.isExpanded, "another app window is outside even when its screen coordinate overlaps the card")
        reveal(12)
        let externalEvent = NSEvent.mouseEvent(with:.leftMouseDown,location:outside,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        controller.observeMouseEvent(externalEvent,isGlobal:true)
        verify(!controller.isExpanded, "other-app mouse-down immediately collapses the card")
        reveal(12.1)
        let cornerEvent = event(.leftMouseDown,at:NSPoint(x:panel.frame.minX+1,y:panel.frame.maxY-1))
        _ = controller.observeLocalMouseEvent(cornerEvent)
        verify(!controller.isExpanded, "a card's transparent corner is an outside click")
        reveal(13)
        func headerPoint(_ x:CGFloat,_ depth:CGFloat) -> NSPoint { panel.convertPoint(toScreen:NSPoint(x:x,y:panel.frame.height-depth)) }
        let headerChecks:[(CGFloat,CGFloat,String)] = [(panel.frame.width/2,3,"top white padding"),(2,30,"left white padding"),(panel.frame.width-2,30,"right white padding"),(panel.frame.width/2,80,"80 pt header bottom boundary")]
        for (x,depth,label) in headerChecks {
            let point = headerPoint(x,depth)
            panel.sendEvent(event(.leftMouseDown,at:point))
            let grabbed = panel.isPressed
            panel.sendEvent(event(.leftMouseUp,at:point))
            verify(grabbed && !panel.isPressed, "actual native down/up captures \(label) without any SwiftUI view registration")
        }
        let initial = panel.frame
        let firstGlobal = headerPoint(panel.frame.width/2,3)
        panel.sendEvent(event(.leftMouseDown,at:firstGlobal))
        controller.collapse(); controller.resetPosition(); evaluate(outside,100)
        controller.updateExpandedHeight(392)
        verify(panel.isPressed && controller.isExpanded && panel.frame == initial && controller.expandedHeight == 280, "actual header press blocks leave and defers dynamic resize while dragging")
        panel.sendEvent(event(.leftMouseUp,at:firstGlobal))
        verify(!panel.isPressed && panel.frame.height == 392 && controller.expandedHeight == 392, "native mouse-up releases the guard and applies requested content height")
        controller.updateExpandedHeight(280)
        let secondGlobal = headerPoint(115,42)
        let dragInitial = panel.frame
        panel.sendEvent(event(.leftMouseDown,at:secondGlobal))
        let beforeRatio = defaults.double(forKey:"gaoyoujian.floating.verticalRatio")
        let offset = NSSize(width:secondGlobal.x-dragInitial.minX,height:secondGlobal.y-dragInitial.minY)
        let middleX = screen.visibleFrame.minX + max(40,floor((screen.visibleFrame.width-dragInitial.width)*0.18))
        let movedGlobal = NSPoint(x:middleX+offset.width,y:screen.visibleFrame.minY+80+offset.height)
        panel.sendEvent(event(.leftMouseDragged,at:movedGlobal))
        let wanted = draggingFrame(pointer:movedGlobal,grabOffset:offset,size:dragInitial.size,in:screen.visibleFrame)
        verify(closeFrame(panel.frame,wanted) && panel.isPressed && controller.dockMode == .free && !controller.isOnLeft && defaults.double(forKey:"gaoyoujian.floating.verticalRatio") == beforeRatio && defaults.string(forKey:"gaoyoujian.floating.dockMode") == "right", "native expanded drag crosses midpoint without changing direction or persisting before release")
        panel.sendEvent(event(.leftMouseUp,at:movedGlobal))
        verify(!panel.isPressed && !controller.isOnLeft && closeFrame(panel.frame,wanted) && defaults.string(forKey:"gaoyoujian.floating.dockMode") == "free" && defaults.double(forKey:"gaoyoujian.floating.verticalRatio") != beforeRatio, "mid-screen release preserves actual expanded position and persists a free anchor")
        let saved = panel.frame
        let savedHorizontal = controller.horizontalRatio, savedVertical = controller.verticalRatio
        let freeRail = Self.placementFrame(size:railHitSize,in:screen.visibleFrame,dock:.free,isLeft:false,horizontalRatio:savedHorizontal,verticalRatio:savedVertical)
        controller.collapse(pointer:outside,now:base.addingTimeInterval(109))
        verify(closeFrame(panel.frame,freeRail) && panel.frame.minX > screen.visibleFrame.minX && panel.frame.maxX < screen.visibleFrame.maxX, "free expanded collapse returns the rail to its saved side/top anchor away from screen edges")
        do {
            let restored = MailFloatingController(store:MailStore(),defaults:defaults)
            restored.suppressPanelPresentationForTesting = true
            restored.restoreIfNeeded()
            let restoredPanel = restored.ensurePanel()
            restored.revealRequiresExit = false
            restored.expand(pointer:outside,now:base)
            verify(restored.dockMode == .free && !restored.isOnLeft && closeFrame(restoredPanel.frame,saved) && !restoredPanel.isVisible, "relaunch restores the free expanded anchor and direction from real isolated preferences")
            restored.hide(); restoredPanel.delegate = nil; restoredPanel.contentView = nil; restoredPanel.close()
        }
        controller.collapse(pointer:outside,now:base.addingTimeInterval(110)); reveal(111)
        let controlPoint = headerPoint(panel.frame.width/2,3)
        let businessPoint = headerPoint(panel.frame.width/2,81)
        let topCorner = headerPoint(1,1)
        verify(closeFrame(panel.frame,saved) && !panel.isGrabEvent(event(.leftMouseDown,at:controlPoint,modifiers:[.control])) && !panel.isGrabEvent(event(.leftMouseDown,at:businessPoint)) && !panel.isGrabEvent(event(.leftMouseDown,at:topCorner)) && !panel.isGrabEvent(event(.rightMouseDown,at:controlPoint)), "fixed native header preserves control/right click, transparent corners and business input just below 80 pt")
        panel.sendEvent(event(.leftMouseDown,at:controlPoint))
        controller.observeMouseEvent(externalEvent,isGlobal:true)
        verify(!panel.isPressed && !controller.isExpanded, "fresh external mouse-down clears an old unmatched press before immediate collapse")
        reveal(112)
        panel.sendEvent(event(.leftMouseDown,at:controlPoint))
        controller.observeMouseEvent(event(.leftMouseUp,at:outside,in:otherWindow),isGlobal:false)
        verify(!panel.isPressed && controller.isExpanded, "a release routed to another native window cannot leave drag protection latched")
        let escape = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:panel.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        panel.keyDown(with:escape)
        verify(!controller.isExpanded && !panel.isPressed && controller.isVisible, "Escape collapses without disabling the feature")
        reveal(113)
        let nearStart = panel.frame
        let nearGrabPoint = headerPoint(115,42)
        let nearOffset = NSSize(width:nearGrabPoint.x-nearStart.minX,height:nearGrabPoint.y-nearStart.minY)
        panel.sendEvent(event(.leftMouseDown,at:nearGrabPoint))
        let nearLeft = NSPoint(x:screen.visibleFrame.minX+20+nearOffset.width,y:screen.visibleFrame.minY+100+nearOffset.height)
        panel.sendEvent(event(.leftMouseDragged,at:nearLeft))
        verify(panel.isPressed && panel.frame.minX == screen.visibleFrame.minX && controller.dockMode == .left && controller.isOnLeft && defaults.string(forKey:"gaoyoujian.floating.dockMode") == "free", "entering the 32 pt left threshold snaps during carry without writing defaults")
        let offLeft = NSPoint(x:screen.visibleFrame.minX+40+nearOffset.width,y:nearLeft.y)
        panel.sendEvent(event(.leftMouseDragged,at:offLeft))
        verify(panel.frame.minX == screen.visibleFrame.minX+40 && controller.dockMode == .free && controller.isOnLeft, "moving beyond threshold immediately leaves the dock without changing original grab offset")
        panel.sendEvent(event(.leftMouseDragged,at:nearLeft))
        let dockedBeforeRelease = panel.frame
        panel.sendEvent(event(.leftMouseUp,at:nearLeft))
        verify(closeFrame(panel.frame,dockedBeforeRelease) && defaults.string(forKey:"gaoyoujian.floating.dockMode") == "left", "docked expanded release persists without a new jump")
        controller.collapse(pointer:outside,now:base.addingTimeInterval(120))
        let railStart = panel.frame
        let railPoint = panel.convertPoint(toScreen:NSPoint(x:10,y:50))
        panel.sendEvent(event(.leftMouseDown,at:railPoint))
        controller.railPointerEntered(); controller.expand(); evaluate(railPoint,200)
        verify(panel.isPressed && !controller.isExpanded && panel.frame == railStart, "native rail press prevents reveal and keeps small physical hit window")
        let railBeforeRatio = defaults.double(forKey:"gaoyoujian.floating.verticalRatio")
        let railTarget = NSPoint(x:screen.visibleFrame.minX+screen.visibleFrame.width*0.6,y:screen.visibleFrame.minY+160)
        panel.sendEvent(event(.leftMouseDragged,at:railTarget))
        let noEarlySave = defaults.double(forKey:"gaoyoujian.floating.verticalRatio") == railBeforeRatio
        panel.sendEvent(event(.leftMouseUp,at:railTarget))
        verify(noEarlySave && !panel.isPressed && !panel.isVisible && !controller.isExpanded && panel.frame.size == railHitSize && !controller.isOnLeft && controller.dockMode == .free && panel.frame.minX > screen.visibleFrame.minX && panel.frame.maxX < screen.visibleFrame.maxX && defaults.string(forKey:"gaoyoujian.floating.dockMode") == "free", "native hidden drag stays a tiny free rail at mid-screen and chooses its inward direction")
        let savedFreeRail = panel.frame
        reveal(210)
        let freeBeforeResize = panel.frame
        let horizontalBeforeResize = controller.horizontalRatio, verticalBeforeResize = controller.verticalRatio
        controller.updateExpandedHeight(1000)
        let heightLimit = min(420,screen.visibleFrame.height)
        verify(controller.expandedHeight == heightLimit && panel.frame.height == heightLimit && !panel.isVisible && controller.horizontalRatio == horizontalBeforeResize && controller.verticalRatio == verticalBeforeResize && panel.frame.maxX == freeBeforeResize.maxX, "natural height changes reflow the free card without changing its canonical anchor")
        controller.collapse(pointer:outside,now:base.addingTimeInterval(211))
        verify(closeFrame(panel.frame,savedFreeRail), "height clamping never overwrites the free hidden rail position")
        controller.rememberedDisplay = "missing-test-display"
        controller.screensChanged()
        verify(controller.rememberedDisplay != "missing-test-display" && controller.horizontalRatio == horizontalBeforeResize && controller.verticalRatio == verticalBeforeResize && controller.dockMode == .free, "display fallback retains canonical free ratios rather than forcing a dock")
        let rightPoint = panel.convertPoint(toScreen:NSPoint(x:10,y:50))
        panel.sendEvent(event(.leftMouseDown,at:rightPoint))
        let nearRight = NSPoint(x:screen.visibleFrame.maxX-12,y:screen.visibleFrame.minY+240)
        panel.sendEvent(event(.leftMouseDragged,at:nearRight))
        verify(panel.isPressed && panel.frame.maxX == screen.visibleFrame.maxX && controller.dockMode == .right && defaults.string(forKey:"gaoyoujian.floating.dockMode") == "free", "a hidden rail snaps to the right during carry without early preference writes")
        panel.sendEvent(event(.leftMouseUp,at:nearRight))
        verify(!panel.isPressed && defaults.string(forKey:"gaoyoujian.floating.dockMode") == "right" && panel.frame.maxX == screen.visibleFrame.maxX, "right rail release persists the existing dock")
        controller.resetPosition()
        verify(controller.dockMode == .right && controller.horizontalRatio == 1 && controller.verticalRatio == 0.15 && defaults.object(forKey:"gaoyoujian.floating.dockMode") == nil && defaults.object(forKey:"gaoyoujian.floating.horizontalRatio") == nil && defaults.bool(forKey:"gaoyoujian.floating.pinned"), "reset clears new position keys while retaining unrelated legacy settings")
        controller.hide()
        verify(controller.eventMonitors.isEmpty && controller.pointerTimer == nil && !controller.isVisible, "disable removes observers and timer")
        controller.show()
        verify(!panel.isVisible && !controller.isExpanded && panel.frame.size == railHitSize && controller.eventMonitors.count == monitorCount, "hidden re-enable starts rail without subscribing to user events")
    }
}
#endif
@main @MainActor struct EdgeGeometryTests {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ name: String) { precondition(value, name); checks += 1 }
        check(MailFloatingController.dragHeaderHeight == 80, "native and visible fixed header share 80 pt")
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
        check(MailFloatingController.dockMode(for:NSRect(x:32,y:20,width:340,height:280),in:screen) == .left, "32 pt boundary enters left dock")
        check(MailFloatingController.dockMode(for:NSRect(x:33,y:20,width:340,height:280),in:screen) == .free, "one point beyond threshold is free")
        check(MailFloatingController.dockMode(for:NSRect(x:screen.maxX-340-32,y:20,width:340,height:280),in:screen) == .right, "32 pt boundary enters right dock")
        check(MailFloatingController.dockMode(for:NSRect(x:400,y:screen.maxY-280,width:340,height:280),in:screen) == .free, "touching top does not add unsolicited top docking")
        check(MailFloatingController.safeRatio(.nan,fallback:0.15) == 0.15 && MailFloatingController.safeRatio(.infinity,fallback:1) == 1 && MailFloatingController.safeRatio(-3,fallback:0.5) == 0 && MailFloatingController.safeRatio(3,fallback:0.5) == 1, "saved free ratios validate and clamp finite values")
        let knownFree = NSRect(x:400,y:200,width:340,height:280)
        for left in [true,false] {
            let ratios = MailFloatingController.anchorRatios(for:knownFree,in:screen,isLeft:left)
            let rail = MailFloatingController.placementFrame(size:MailFloatingController.railHitSize,in:screen,dock:.free,isLeft:left,horizontalRatio:ratios.horizontal,verticalRatio:ratios.vertical)
            let card = MailFloatingController.placementFrame(size:knownFree.size,in:screen,dock:.free,isLeft:left,horizontalRatio:ratios.horizontal,verticalRatio:ratios.vertical)
            let expectedRail = NSRect(x:left ? 400 : 720,y:376,width:20,height:104)
            check(abs(rail.minX-expectedRail.minX) < 0.01 && abs(rail.minY-expectedRail.minY) < 0.01, "a free card restores the known top/side rail anchor")
            check(abs(card.minX-knownFree.minX) < 0.01 && abs(card.minY-knownFree.minY) < 0.01, "free expand/collapse restores the actual card rather than the nearest screen edge")
            let alternate = screens[1]
            let shiftedRail = MailFloatingController.placementFrame(size:MailFloatingController.railHitSize,in:alternate,dock:.free,isLeft:left,horizontalRatio:ratios.horizontal,verticalRatio:ratios.vertical)
            let shiftedCard = MailFloatingController.placementFrame(size:NSSize(width:340,height:420),in:alternate,dock:.free,isLeft:left,horizontalRatio:ratios.horizontal,verticalRatio:ratios.vertical)
            check(alternate.contains(shiftedRail) && alternate.contains(shiftedCard) && shiftedCard.insetBy(dx:-0.01,dy:-0.01).contains(shiftedRail), "canonical ratios remain reachable on a different screen with negative coordinates")
        }
        let crossed = NSRect(x:100,y:200,width:340,height:280)
        let crossedRatios = MailFloatingController.anchorRatios(for:crossed,in:screen,isLeft:false)
        let crossedRestored = MailFloatingController.placementFrame(size:crossed.size,in:screen,dock:.free,isLeft:false,horizontalRatio:crossedRatios.horizontal,verticalRatio:crossedRatios.vertical)
        check(crossedRatios.horizontal < 0.5 && abs(crossedRestored.minX-crossed.minX) < 0.01, "cross-midpoint expanded free drag retains direction without a 320 pt jump")
        let taller = MailFloatingController.placementFrame(size:NSSize(width:340,height:420),in:screen,dock:.free,isLeft:false,horizontalRatio:crossedRatios.horizontal,verticalRatio:crossedRatios.vertical)
        check(abs(taller.maxX-crossed.maxX) < 0.01 && abs(taller.maxY-crossed.maxY) < 0.01, "free content height change preserves canonical top and side")
        let bottomRail = MailFloatingController.placementFrame(size:MailFloatingController.railHitSize,in:screen,dock:.free,isLeft:false,horizontalRatio:0.6,verticalRatio:1)
        let bottomCard = MailFloatingController.placementFrame(size:NSSize(width:340,height:420),in:screen,dock:.free,isLeft:false,horizontalRatio:0.6,verticalRatio:1)
        check(bottomRail.minY == screen.minY && screen.contains(bottomCard) && bottomCard.contains(bottomRail), "a bottom free anchor survives larger-card clamping")
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
