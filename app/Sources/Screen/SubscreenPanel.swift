import SwiftUI
import AppKit

/// 副屏面板：无边框、非激活（点它不抢主屏焦点），屏蔽级盖住副屏的菜单栏。
final class SubscreenPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = true
        backgroundColor = .black
        isMovable = false
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        isFloatingPanel = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 后台窗口的第一次点击默认只用来激活窗口；这里让它直接触发按钮。
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    required init(rootView: Content) { super.init(rootView: rootView) }
    @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

enum Displays {
    static func primaryID() -> CGDirectDisplayID { CGMainDisplayID() }

    static func id(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func uuid(of id: CGDirectDisplayID) -> String {
        guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, u) as String
    }

    static func all() -> [DisplayInfo] {
        NSScreen.screens.map { s in
            let id = id(of: s)
            return DisplayInfo(id: id, uuid: uuid(of: id), name: s.localizedName, frame: s.frame, isPrimary: id == primaryID())
        }
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? { NSScreen.screens.first { self.id(of: $0) == id } }

    /// 主屏可见区域（CG 坐标）。
    static func primaryVisibleCG() -> CGRect? {
        guard let s = screen(for: primaryID()) else { return nil }
        return ScreenGeometry.appKitToCG(s.visibleFrame, primaryHeight: CGDisplayBounds(primaryID()).height)
    }
}

/// 右上角那组按钮显不显示。鼠标进到右上角的悬停区就显示，离开 1.5 秒后收起。
final class ChromeState: ObservableObject {
    @Published var visible = false
}

/// 盖在面板上的悬停区，不接点击，只用跟踪区域收鼠标进出（非激活面板也收得到）。
final class HoverZoneView: NSView {
    var onChange: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?
    private var hideWork: DispatchWorkItem?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        // 画布右上角 520 × 140（视图坐标原点在左下），按画布缩放和居中换算到面板坐标。
        let s = min(bounds.width / 1280, bounds.height / 720)
        let cw = 1280 * s, ch = 720 * s
        let ox = (bounds.width - cw) / 2, oy = (bounds.height - ch) / 2
        let rect = NSRect(x: ox + cw - 520 * s, y: oy + ch - 140 * s, width: 520 * s, height: 140 * s)
        let a = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) {
        hideWork?.cancel()
        onChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.onChange(false) }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
    }
}
