import Foundation
import CoreGraphics

func runEvictGeometryTests() {
    let target = CGRect(x: -1280, y: 0, width: 1280, height: 720)
    let appKitTarget = CGRect(x: -1280, y: 549, width: 1280, height: 720)
    let primaryHeight: CGFloat = 1269
    let visible = ScreenGeometry.appKitToCG(CGRect(x: 0, y: 91, width: 3008, height: 1148),
                                            primaryHeight: primaryHeight)
    expectEqual(visible, CGRect(x: 0, y: 30, width: 3008, height: 1148), "main visible frame to CG")
    expectEqual(ScreenGeometry.appKitToCG(appKitTarget, primaryHeight: primaryHeight), target,
                "left screen with unaligned bottom; 1x and 2x coordinates stay in points")
    expectEqual(ScreenGeometry.cgToAppKit(target, primaryHeight: primaryHeight), appKitTarget, "inverse left screen")
    let above = CGRect(x: 240, y: 1269, width: 1280, height: 720)
    let aboveCG = CGRect(x: 240, y: -720, width: 1280, height: 720)
    expectEqual(ScreenGeometry.appKitToCG(above, primaryHeight: primaryHeight), aboveCG, "screen above primary")
    expectEqual(ScreenGeometry.cgToAppKit(aboveCG, primaryHeight: primaryHeight), above, "inverse above screen")
    expectFalse(ScreenGeometry.isOnTarget(CGRect(x: 0, y: 100, width: 400, height: 300), target: target), "shared edge")
    expectFalse(ScreenGeometry.isOnTarget(CGRect(x: -8, y: 100, width: 400, height: 300), target: target), "exactly 8 points")
    expectFalse(ScreenGeometry.isOnTarget(CGRect(x: -400, y: 712, width: 400, height: 300), target: target), "height must exceed 8 too")
    expectTrue(ScreenGeometry.isOnTarget(CGRect(x: -100, y: 100, width: 400, height: 300), target: target), "100 points inside")
    expectTrue(ScreenGeometry.isOnTarget(CGRect(x: -900, y: 100, width: 400, height: 300), target: target), "whole window inside")
    expectFalse(ScreenGeometry.isOnTarget(CGRect(x: 4000, y: 100, width: 400, height: 300), target: target), "disjoint")
    for source in [target, aboveCG] {
        for window in [CGRect(x: source.minX + 100, y: source.minY + 100, width: 400, height: 300),
                       CGRect(x: source.maxX - 100, y: source.minY, width: 400, height: 300),
                       CGRect(x: source.minX, y: source.minY, width: 5000, height: 3000)] {
            let moved = ScreenGeometry.relocate(window, from: source, into: visible)
            expectTrue(visible.contains(moved), "relocated window fully inside primary visible frame")
            expectFalse(ScreenGeometry.isOnTarget(moved, target: source, minOverlap: 0), "no target overlap at all")
            expectEqual(moved.size, CGSize(width: min(window.width, visible.width), height: min(window.height, visible.height)),
                        "only shrink dimensions exceeding visible area")
        }
    }
    let centered = CGRect(x: target.midX - 200, y: target.midY - 150, width: 400, height: 300)
    let centeredResult = ScreenGeometry.relocate(centered, from: target, into: visible)
    expectEqual(centeredResult.midX, visible.midX, "relative horizontal center preserved")
    expectEqual(centeredResult.midY, visible.midY, "relative vertical center preserved")
    let huge = ScreenGeometry.relocate(CGRect(x: -1280, y: 0, width: 5000, height: 3000), from: target, into: visible)
    expectEqual(huge, visible, "oversize window shrinks to visible bounds")

    var tracker = EvictionTracker()
    expectEqual(tracker.decide(windowKey: "a", now: 0), .move, "first move")
    expectEqual(tracker.decide(windowKey: "a", now: 1), .move, "second move")
    expectEqual(tracker.decide(windowKey: "a", now: 2), .move, "third move allowed")
    expectEqual(tracker.decide(windowKey: "a", now: 3), .giveUp, "fourth triggers cooldown")
    expectEqual(tracker.decide(windowKey: "a", now: 62.999), .giveUp, "cooldown not extended by checks")
    expectEqual(tracker.decide(windowKey: "a", now: 63), .move, "restored after exactly 60 seconds")
    expectEqual(tracker.decide(windowKey: "b", now: 63), .move, "windows tracked independently")
    var sliding = EvictionTracker()
    for time in [0.0, 4, 8, 10, 14] {
        expectEqual(sliding.decide(windowKey: "a", now: time), .move, "sliding half-open 10-second window at \(time)")
    }
    expectEqual(sliding.decide(windowKey: "a", now: 15), .giveUp, "three recent moves still count")
    sliding.forget(windowKey: "a")
    expectEqual(sliding.decide(windowKey: "a", now: 16), .move, "forget clears cooldown")
    print("EvictGeometryTests passed")
}
