import Foundation
import CoreGraphics

func runScreenModelTests() {
    let main = DisplayInfo(id: 1, uuid: "MAIN", name: "LG ULTRAGEAR+", frame: CGRect(x: 0, y: 0, width: 3008, height: 1269), isPrimary: true)
    let wokyis = DisplayInfo(id: 2, uuid: "244BE832", name: "Wokyis", frame: CGRect(x: -1280, y: 549, width: 1280, height: 720), isPrimary: false)
    let other = DisplayInfo(id: 3, uuid: "OTHER", name: "Studio", frame: CGRect(x: 3008, y: 0, width: 1920, height: 1080), isPrimary: false)
    let wokyis2 = DisplayInfo(id: 4, uuid: "SECOND", name: "Wokyis", frame: CGRect(x: 3008, y: 0, width: 1280, height: 720), isPrimary: false)

    // 目标屏解析
    expectEqual(TargetResolver.resolve(displays: [main, wokyis], preferredUUID: "244BE832", preferredName: "Wokyis"), wokyis, "UUID hit")
    expectEqual(TargetResolver.resolve(displays: [main, wokyis], preferredUUID: "GONE", preferredName: "Wokyis"), wokyis, "UUID miss falls back to name")
    expectEqual(TargetResolver.resolve(displays: [main, other], preferredUUID: "244BE832", preferredName: "Wokyis"), nil, "remembered screen missing: never another screen")
    expectEqual(TargetResolver.resolve(displays: [main, other, wokyis], preferredUUID: nil, preferredName: ""), wokyis, "first run: smallest non-primary display")
    expectEqual(TargetResolver.resolve(displays: [main, other], preferredUUID: nil, preferredName: ""), other, "first run with one external display")
    expectEqual(TargetResolver.resolve(displays: [main], preferredUUID: nil, preferredName: "Wokyis"), nil, "no target never returns main")
    expectEqual(TargetResolver.resolve(displays: [main, wokyis2, wokyis], preferredUUID: nil, preferredName: "Wokyis"), wokyis, "same-name screens pick lowest id")
    expectEqual(TargetResolver.resolve(displays: [main, wokyis2, wokyis], preferredUUID: "SECOND", preferredName: "Wokyis"), wokyis2, "UUID beats name order")
    let mainNamedWokyis = DisplayInfo(id: 1, uuid: "244BE832", name: "Wokyis", frame: main.frame, isPrimary: true)
    expectEqual(TargetResolver.resolve(displays: [mainNamedWokyis], preferredUUID: "244BE832", preferredName: "Wokyis"), nil, "primary display is never a target")

    // 状态机
    var sm = WindowStateMachine()
    expectEqual(sm.handle(.displaysChanged(target: wokyis)), [.show(frame: wokyis.frame), .status(nil)], "connect shows on target")
    expectEqual(sm.handle(.selfCheck(frameOK: true, visible: true)), [], "healthy self check does nothing")
    expectEqual(sm.handle(.selfCheck(frameOK: false, visible: true)), [.show(frame: wokyis.frame)], "bad frame re-shows in takeover")
    expectEqual(sm.handle(.stuckChanged(apps: ["TestWindows"])), [.hide, .status("副屏上有无法移走的窗口：TestWindows")], "stuck window yields")
    expectEqual(sm.mode, .yielded(apps: ["TestWindows"]), "mode yielded")
    expectEqual(sm.handle(.selfCheck(frameOK: false, visible: false)), [], "self check never re-covers while yielded")
    expectEqual(sm.handle(.repin), [.rescan], "repin while yielded only rescans")
    let afterWake = sm.handle(.displaysChanged(target: wokyis))
    expectFalse(afterWake.contains(.show(frame: wokyis.frame)), "wake reposition never re-covers while yielded")
    expectEqual(sm.handle(.stuckChanged(apps: [])), [.show(frame: wokyis.frame), .status(nil)], "clean target returns to takeover")
    expectEqual(sm.handle(.displaysChanged(target: nil)), [.hide, .status("副屏未连接")], "disconnect hides")
    expectEqual(sm.handle(.selfCheck(frameOK: false, visible: false)), [], "missing target never shows")
    expectEqual(sm.handle(.stuckChanged(apps: ["X"])), [], "missing target outranks stuck")
    expectEqual(sm.mode, .targetMissing, "still missing")
    _ = sm.handle(.stuckChanged(apps: []))
    expectEqual(sm.handle(.displaysChanged(target: wokyis)), [.show(frame: wokyis.frame), .status(nil)], "reconnect shows again")
    expectEqual(sm.handle(.repin), [.show(frame: wokyis.frame), .status(nil)], "repin in takeover re-shows")
    print("ScreenModelTests passed")
}
