import AppKit
import SwiftUI
@MainActor final class MailStore {}
struct MailFloatingView: View {
    let store: MailStore
    @ObservedObject var controller: MailFloatingController
    var body: some View {
        if controller.isExpanded { Text("Test").frame(maxWidth:.infinity,maxHeight:.infinity) }
        else { MailFloatingRailView(controller:controller) }
    }
}
import AppKit
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
        print("Edge floating geometry: \(checks) assertions passed")
    }
}
