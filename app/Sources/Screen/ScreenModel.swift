// reverie:logic 纯逻辑，单元测试会编进来，不许依赖 SwiftUI / AppKit。
import Foundation
import CoreGraphics

/// 一块显示器的描述（AppKit 坐标）。由 AppKit 层从 NSScreen 生成，逻辑层只看这些字段。
struct DisplayInfo: Equatable {
    let id: UInt32
    let uuid: String
    let name: String
    let frame: CGRect
    let isPrimary: Bool      // CGMainDisplayID 那块（菜单栏所在、全局坐标原点）
}

enum TargetResolver {
    /// 解析顺序：记住的 UUID → 名字 → （只在还没记住任何屏时）最小的那块非主屏 → 无。绝不退到主屏。
    /// 记住了某块屏之后它不在就隐藏，不会跑到别的屏上去。
    static func resolve(displays: [DisplayInfo], preferredUUID: String?, preferredName: String) -> DisplayInfo? {
        if let uuid = preferredUUID, !uuid.isEmpty, let hit = displays.first(where: { $0.uuid == uuid && !$0.isPrimary }) {
            return hit
        }
        if !preferredName.isEmpty,
           let byName = displays.filter({ $0.name == preferredName && !$0.isPrimary }).sorted(by: { $0.id < $1.id }).first {
            return byName
        }
        guard preferredUUID == nil || preferredUUID == "" else { return nil }
        return displays
            .filter { !$0.isPrimary }
            .sorted { a, b in
                let sa = a.frame.width * a.frame.height, sb = b.frame.width * b.frame.height
                return sa == sb ? a.id < b.id : sa < sb
            }
            .first
    }
}

/// 副屏窗口的状态。只有 takeover 会上屏。
enum WindowMode: Equatable {
    case takeover(frame: CGRect)
    case yielded(apps: [String])     // 副屏上有挪不动的窗口，Reverie 整个隐藏让它露出来
    case targetMissing
}

enum WindowEvent: Equatable {
    case displaysChanged(target: DisplayInfo?)
    case stuckChanged(apps: [String])     // 空数组 = 副屏干净
    case selfCheck(frameOK: Bool, visible: Bool)
    case repin
}

enum WindowAction: Equatable {
    case show(frame: CGRect)     // 设屏蔽级、设边界、前置
    case hide
    case rescan                  // 让驱逐器立刻重扫一次
    case status(String?)         // 菜单栏提示；nil 表示清掉
}

struct WindowStateMachine {
    private(set) var mode: WindowMode = .targetMissing
    private var target: DisplayInfo?
    private var stuck: [String] = []

    /// 重定位、自检、重新固定都只提交事件，由这里决定动作；只有接管状态会输出 show。
    mutating func handle(_ event: WindowEvent) -> [WindowAction] {
        switch event {
        case .displaysChanged(let t):
            target = t
            return settle(force: true)
        case .stuckChanged(let apps):
            stuck = apps
            return settle(force: false)
        case .selfCheck(let frameOK, let visible):
            if case .takeover(let f) = mode, !(frameOK && visible) { return [.show(frame: f)] }
            return []
        case .repin:
            if case .yielded = mode { return [.rescan] }
            return settle(force: true)
        }
    }

    private mutating func settle(force: Bool) -> [WindowAction] {
        let next: WindowMode
        if let t = target {
            next = stuck.isEmpty ? .takeover(frame: t.frame) : .yielded(apps: stuck)
        } else {
            next = .targetMissing
        }
        guard force || next != mode else { return [] }
        let changed = next != mode
        mode = next
        switch next {
        case .targetMissing:
            return changed || force ? [.hide, .status("副屏未连接")] : []
        case .yielded(let apps):
            return [.hide, .status("副屏上有无法移走的窗口：" + apps.joined(separator: "、"))]
        case .takeover(let f):
            return [.show(frame: f), .status(nil)]
        }
    }
}
