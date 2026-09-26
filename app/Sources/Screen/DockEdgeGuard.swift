import AppKit

/// 不让程序坞搬到副屏。macOS 在「显示器具有单独的空间」下，鼠标顶到哪块屏的程序坞那条边（通常是底边），
/// 程序坞就搬到哪块屏。副屏的这条边如果空着（旁边没有别的屏），鼠标一碰到就把它往里推回 16pt。
/// 这层视图盖在面板上、不接点击，只用跟踪区域收「鼠标进入 / 移动」；面板让出（隐藏）时自然不起作用。
final class DockEdgeGuardView: NSView {
    enum Edge { case bottom, left, right }

    var targetBoundsCG: () -> CGRect? = { nil }
    var isActive: () -> Bool = { true }
    private var area: NSTrackingArea?
    private var edge: Edge?
    private static let band: CGFloat = 6

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 副屏位置、显示器排列变了以后调用。
    func refresh() {
        if let area { removeTrackingArea(area) }
        area = nil
        edge = targetBoundsCG().flatMap(Self.freeDockEdge)
        guard let edge else { return }
        let rect: NSRect
        switch edge {
        case .bottom: rect = NSRect(x: 0, y: 0, width: bounds.width, height: Self.band)
        case .left: rect = NSRect(x: 0, y: 0, width: Self.band, height: bounds.height)
        case .right: rect = NSRect(x: bounds.width - Self.band, y: 0, width: Self.band, height: bounds.height)
        }
        let a = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refresh()
    }

    override func mouseEntered(with event: NSEvent) { push() }
    override func mouseMoved(with event: NSEvent) { push() }

    private func push() {
        guard isActive(), let edge, let t = targetBoundsCG(), let p = CGEvent(source: nil)?.location else { return }
        var q = p
        switch edge {
        case .bottom: q.y = min(p.y, t.maxY - 16)
        case .left: q.x = max(p.x, t.minX + 16)
        case .right: q.x = min(p.x, t.maxX - 16)
        }
        guard q != p else { return }
        CGWarpMouseCursorPosition(q)
        CGAssociateMouseAndMouseCursorPosition(1)   // 取消挪动光标后默认的短暂卡顿
    }

    /// 程序坞在哪条边（读系统的程序坞设置），以及副屏的这条边是不是空着。挨着别的屏就不管，免得挡住鼠标过屏。
    static func freeDockEdge(target t: CGRect) -> Edge? {
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        let edge: Edge = orientation == "left" ? .left : (orientation == "right" ? .right : .bottom)
        let probe: CGRect
        switch edge {
        case .bottom: probe = CGRect(x: t.minX, y: t.maxY, width: t.width, height: 2)
        case .left: probe = CGRect(x: t.minX - 2, y: t.minY, width: 2, height: t.height)
        case .right: probe = CGRect(x: t.maxX, y: t.minY, width: 2, height: t.height)
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return nil }
        for id in ids.prefix(Int(count)) {
            let b = CGDisplayBounds(id)
            if b != t && b.intersects(probe) { return nil }
        }
        return edge
    }
}
