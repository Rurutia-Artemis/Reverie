// reverie:logic 纯逻辑，单元测试会编进来，不许依赖 SwiftUI / AppKit。
import Foundation
import CoreGraphics

enum ScreenGeometry {
    static func appKitToCG(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func cgToAppKit(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        appKitToCG(r, primaryHeight: primaryHeight)
    }

    static func isOnTarget(_ window: CGRect, target: CGRect, minOverlap: CGFloat = 8) -> Bool {
        let overlap = window.intersection(target)
        return !overlap.isNull && overlap.width > minOverlap && overlap.height > minOverlap
    }

    /// Screen rectangles must be nonempty and have disjoint interiors (physical displays).
    static func relocate(_ window: CGRect, from target: CGRect, into visible: CGRect) -> CGRect {
        precondition(!target.isEmpty && !visible.isEmpty)
        let overlap = target.intersection(visible)
        precondition(overlap.isNull || overlap.width == 0 || overlap.height == 0)
        let size = CGSize(width: min(window.width, visible.width),
                          height: min(window.height, visible.height))
        // Normalize the available travel, preserving left/right and top/bottom alignment.
        func fraction(_ origin: CGFloat, _ base: CGFloat, _ travel: CGFloat) -> CGFloat {
            travel > 0 ? min(1, max(0, (origin - base) / travel)) : 0
        }
        let x = visible.minX + fraction(window.minX, target.minX, target.width - window.width)
            * (visible.width - size.width)
        let y = visible.minY + fraction(window.minY, target.minY, target.height - window.height)
            * (visible.height - size.height)
        return CGRect(origin: CGPoint(x: min(x, visible.maxX - size.width),
                                      y: min(y, visible.maxY - size.height)), size: size)
    }
}

struct EvictionTracker {
    enum Decision: Equatable { case move, giveUp }
    private struct History {
        var moves: [TimeInterval] = []
        var giveUpUntil: TimeInterval?
    }
    private var histories: [String: History] = [:]

    mutating func decide(windowKey: String, now: TimeInterval) -> Decision {
        // Expire absent windows as well, without forgetting a window between bounces.
        histories = histories.filter { _, h in
            (h.giveUpUntil.map { now < $0 } ?? false) || h.moves.contains { now - $0 < 10 }
        }
        var h = histories[windowKey] ?? History()
        if let until = h.giveUpUntil {
            if now < until { return .giveUp }
            h = History()
        }
        h.moves.removeAll { now - $0 >= 10 }
        if h.moves.count >= 3 {
            h.giveUpUntil = now + 60
            histories[windowKey] = h
            return .giveUp
        }
        h.moves.append(now)
        histories[windowKey] = h
        return .move
    }

    mutating func forget(windowKey: String) {
        histories.removeValue(forKey: windowKey)
    }
}
